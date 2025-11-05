const std = @import("std");
const Allocator = std.mem.Allocator;

const vaxis = @import("vaxis");

const utils = @import("../utils.zig");
const input = @import("input.zig");
const History = @import("History.zig");
const Position = @import("Position.zig");

const Repl = @This();

const InternalEvent = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
};

const Loop = vaxis.Loop(InternalEvent);

pub const UserFacingEvent = union(enum) {
    /// program must exit with the given code
    exit: u8,
    input: []const u8,
};

allocator: Allocator,
history: History,
loop: Loop,
pos: Position,
text: vaxis.widgets.TextInput,
tty: vaxis.Tty,
vx: vaxis.Vaxis,
win: vaxis.Window,

/// WARNING: returns a partially-initialized instance, must call .init()
pub fn create(allocator: Allocator) Repl {
    return .{
        .allocator = allocator,
        .history = .empty,
        .loop = undefined,
        .pos = .zero,
        .text = .init(allocator),
        .tty = undefined,
        .vx = undefined,
        .win = undefined,
    };
}

pub fn init(self: *Repl, buffer: []u8) !void {
    errdefer self.text.deinit();

    self.tty = try .init(buffer);
    errdefer self.tty.deinit();

    self.vx = try vaxis.init(self.allocator, .{});
    errdefer self.vx.deinit(self.allocator, self.tty.writer());

    self.win = self.vx.window();

    self.loop = .{
        .tty = &self.tty,
        .vaxis = &self.vx,
    };
    try self.loop.init();

    try self.loop.start();
    errdefer self.loop.stop();

    try self.vx.enterAltScreen(self.tty.writer());
    try self.vx.queryTerminal(self.tty.writer(), std.time.ns_per_s);
}

pub fn destroy(self: *Repl) void {
    self.text.deinit();
    self.loop.stop();
    self.vx.deinit(self.allocator, self.tty.writer());
    self.tty.deinit();
}

// TODO: make full rendering based on history
pub fn render(self: *Repl) !void {
    try self.vx.render(self.tty.writer());
}

pub fn advanceLine(self: *Repl) Allocator.Error!void {
    self.pos.advanceLine();
    _ = try self.history.addLine(self.allocator);
}

fn lastLine(self: *Repl) Allocator.Error!*History.Line {
    return self.history.first() orelse try self.history.addLine(self.allocator);
}

pub fn print(self: *Repl, texts: []const []const u8, style: vaxis.Style) Allocator.Error!void {
    const line = try self.lastLine();

    for (texts) |text| {
        const copy = try line.append(self.allocator, text);

        const res = self.win.print(
            &.{
                .{ .text = copy, .style = style },
            },
            self.pos.toOptions(),
        );

        self.pos.update(res);
    }
}

pub fn printLink(self: *Repl, texts: []const []const u8, link: vaxis.Cell.Hyperlink) Allocator.Error!void {
    const line = try self.lastLine();

    for (texts) |text| {
        const copy = try line.append(self.allocator, text);

        const res = self.win.print(
            &.{
                .{ .text = copy, .link = link },
            },
            self.pos.toOptions(),
        );

        self.pos.update(res);
    }
}

pub fn printInNewLine(self: *Repl, texts: []const []const u8, style: vaxis.Style) Allocator.Error!void {
    try self.advanceLine();
    try self.print(texts, style);
    try self.advanceLine();
}

pub fn showPromptAndInput(self: *Repl) Allocator.Error!void {
    self.pos.col = 0;

    try self.print(&.{"collector>"}, .{ .bold = true });
    try self.print(&.{self.text.buf.firstHalf()}, .{});
    self.win.showCursor(self.pos.col, self.pos.row);
    try self.print(&.{self.text.buf.secondHalf()}, .{});
}

pub fn warn(self: *Repl, texts: []const []const u8) Allocator.Error!void {
    return self.printInNewLine(texts, .{ .fg = .{ .rgb = .{ 255, 165, 0 } } });
}

pub fn err(self: *Repl, texts: []const []const u8) Allocator.Error!void {
    return self.printInNewLine(texts, .{ .fg = .{ .rgb = .{ 255, 0, 0 } } });
}

/// takes care of rendering the window contents and restarting screen
/// as such, when control is given back to user, only other drawing must be performed
pub fn nextEvent(self: *Repl) !?UserFacingEvent {
    const event = self.loop.nextEvent();
    switch (event) {
        .key_press => |key| {
            for (input.handlers) |handler| {
                switch (handler(self, key)) {
                    .noop => {},
                    .done => {
                        try self.showPromptAndInput();
                        try self.render();
                        return null;
                    },
                    .hint => |hint| {
                        try self.showPromptAndInput();
                        try self.printInNewLine(&.{hint}, .{});
                        try self.render();
                        return null;
                    },
                    .exit => |code| {
                        return .{ .exit = code };
                    },
                }
            }

            // append to input
            if (key.codepoint != vaxis.Key.enter) {
                if (key.text) |text| {
                    try self.text.insertSliceAtCursor(text);
                }

                try self.showPromptAndInput();
                try self.render();
                return null;
            }

            // defer input handling to the application
            return .{ .input = try self.text.buf.toOwnedSlice() };
        },
        .winsize => |winsize| {
            try self.vx.resize(self.allocator, self.tty.writer(), winsize);
            self.win = self.vx.window();

            self.win.clear();
            try self.showPromptAndInput();
            try self.render();
            return null;
        },
    }
}
