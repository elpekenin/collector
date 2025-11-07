//! Common logic provided by any REPL application
//!
//! AKA: Tiny wrapper around vaxis' event loop, handling Ctrl+C, Ctrl+D, arrows, appending input, ...
//!
//! Will yield back to user upon exit request or end of user input (enter key pressed)

const std = @import("std");
const Allocator = std.mem.Allocator;

const vaxis = @import("vaxis");
const Key = vaxis.Key;

const History = @import("History.zig");
const Line = @import("Line.zig");
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

pub const styles = struct {
    pub const green: vaxis.Style = .{ .fg = .{ .rgb = .{ 0, 255, 0 } } };
    pub const orange: vaxis.Style = .{ .fg = .{ .rgb = .{ 255, 165, 0 } } };
    pub const red: vaxis.Style = .{ .fg = .{ .rgb = .{ 255, 0, 0 } } };
};

allocator: Allocator,
history: History,
/// input status (what's written and where)
input: struct {
    buf: vaxis.widgets.TextInput,
    // TODO: remove this field implementing history.getLastInput or something like that instead
    line: u16,
},
loop: Loop,
tty: vaxis.Tty,
vx: vaxis.Vaxis,
win: vaxis.Window,

/// WARNING: returns a partially-initialized instance, must call .init()
pub fn create(allocator: Allocator) Repl {
    return .{
        .allocator = allocator,
        .history = .empty,
        .input = .{
            .line = 0,
            .buf = .init(allocator),
        },
        .loop = undefined,
        .tty = undefined,
        .vx = undefined,
        .win = undefined,
    };
}

pub fn init(self: *Repl, buffer: []u8) !void {
    self.tty = try .init(buffer);

    self.vx = try vaxis.init(self.allocator, .{});

    self.win = self.vx.window();

    self.loop = .{
        .tty = &self.tty,
        .vaxis = &self.vx,
    };
    try self.loop.init();

    try self.loop.start();

    try self.vx.enterAltScreen(self.tty.writer());
    try self.vx.queryTerminal(self.tty.writer(), std.time.ns_per_s);

    try self.newPrompt();
}

pub fn deinit(self: *Repl) void {
    self.history.deinit(self.allocator);
    self.input.buf.deinit();
    self.loop.stop();
    self.vx.deinit(self.allocator, self.tty.writer());
    self.tty.deinit();
}

pub fn newPrompt(self: *Repl) Allocator.Error!void {
    try self.addLine();

    const entry = self.history.lastEntry();
    entry.is_input = true;

    // reset history lookup
    self.history.cursor = null;

    self.input.line = @intCast(self.history.getLen() - 1);
}

pub fn render(self: *Repl) !void {
    self.win.clear();

    var pos: Position = .zero;
    for (self.history.entries.items, 0..) |entry, i| {
        if (entry.is_input) {
            pos.set(
                self.win.print(
                    &.{
                        .{
                            .text = "collector> ",
                            .style = .{ .bold = true },
                        },
                    },
                    pos.toOptions(),
                ),
            );
        }

        pos.set(
            self.win.print(
                entry.line.segments.items,
                pos.toOptions(),
            ),
        );

        if (self.input.line == i) {
            pos.set(
                self.win.print(
                    &.{
                        .{ .text = self.input.buf.buf.firstHalf() },
                    },
                    pos.toOptions(),
                ),
            );

            self.win.showCursor(pos.col, pos.row);

            pos.set(
                self.win.print(
                    &.{
                        .{ .text = self.input.buf.buf.secondHalf() },
                    },
                    pos.toOptions(),
                ),
            );
        }

        pos.advanceLine();
    }

    try self.vx.render(self.tty.writer());
}

pub fn addLine(self: *Repl) Allocator.Error!void {
    // if input won't fit, remove previous items from history
    if (self.win.height > 0 and self.history.entries.items.len >= self.win.height) {
        var removed = self.history.popFirst();
        removed.deinit(self.allocator);
    }

    try self.history.entries.append(self.allocator, .empty);
}

/// add text to current line
pub fn print(self: *Repl, segments: []const vaxis.Segment) Allocator.Error!void {
    const line = self.history.lastLine();

    for (segments) |segment| {
        try line.append(self.allocator, segment);
    }
}

/// create a new line and print to it
pub fn printInNewLine(self: *Repl, segments: []const vaxis.Segment) Allocator.Error!void {
    try self.addLine();
    try self.print(segments);
}

pub fn storeInput(self: *Repl, input: []const u8) Allocator.Error!void {
    try self.print(&.{
        .{ .text = input },
    });

    const entry = self.history.lastEntry();
    std.debug.assert(entry.is_input == true);
}

fn output(self: *Repl, texts: []const []const u8, style: vaxis.Style) Allocator.Error!void {
    try self.addLine();

    const line = self.history.lastLine();
    for (texts) |text| {
        try line.append(self.allocator, .{
            .text = text,
            .style = style,
        });
    }

    try self.newPrompt();
}

pub fn success(self: *Repl, texts: []const []const u8) Allocator.Error!void {
    return self.output(texts, styles.green);
}

pub fn warn(self: *Repl, texts: []const []const u8) Allocator.Error!void {
    return self.output(texts, styles.orange);
}

pub fn err(self: *Repl, texts: []const []const u8) Allocator.Error!void {
    return self.output(texts, styles.red);
}

/// takes care of rendering the window contents and restarting screen
/// as such, when control is given back to user, only other drawing must be performed
pub fn nextEvent(self: *Repl) !?UserFacingEvent {
    const event = self.loop.nextEvent();
    switch (event) {
        .key_press => |key| {
            for (handlers) |handler| {
                switch (try handler(self, key)) {
                    .noop => {},
                    .done => {
                        try self.render();
                        return null;
                    },
                    .exit => |code| return .{ .exit = code },
                }
            }

            // append to input
            if (key.codepoint != vaxis.Key.enter) {
                if (key.text) |text| {
                    try self.input.buf.insertSliceAtCursor(text);
                }

                try self.render();
                return null;
            }

            // defer input handling to the application
            return .{ .input = try self.input.buf.toOwnedSlice() };
        },
        .winsize => |winsize| {
            try self.vx.resize(self.allocator, self.tty.writer(), winsize);
            self.win = self.vx.window();

            self.win.clear();

            try self.render();
            return null;
        },
    }
}

const HandlerResult = anyerror!union(enum) {
    noop,
    done,
    exit: u8,
};

fn ctrlCombinations(self: *Repl, key: Key) HandlerResult {
    if (!key.mods.ctrl) return .noop;

    const empty_input = self.input.buf.buf.realLength() == 0;

    // Ctrl+D + empty input => exit
    switch (key.codepoint) {
        'd' => {
            if (empty_input) {
                return .{ .exit = 0 };
            }

            return .done;
        },

        // Ctrl+C => clear input
        'c' => {
            if (!empty_input) {
                self.input.buf.clearRetainingCapacity();
            }

            return .done;
        },

        else => return .noop,
    }
}

fn arrows(self: *Repl, key: Key) HandlerResult {
    switch (key.codepoint) {
        Key.left => {
            if (key.mods.ctrl) {
                self.input.buf.moveBackwardWordwise();
            } else {
                self.input.buf.cursorLeft();
            }

            return .done;
        },

        Key.right => {
            if (key.mods.ctrl) {
                self.input.buf.moveForwardWordwise();
            } else {
                self.input.buf.cursorRight();
            }

            return .done;
        },

        Key.up,
        Key.down,
        => |cp| {
            // TODO: do not copy empty lines
            if (cp == Key.up) {
                self.history.moveCursorUp();
            } else {
                self.history.moveCursorDown();
            }

            if (self.history.getSelectedEntry()) |entry| {
                const input = try entry.line.toOwnedSlice(self.allocator);
                defer self.allocator.free(input);

                self.input.buf.clearRetainingCapacity();

                try self.input.buf.insertSliceAtCursor(input);
            }

            return .done;
        },

        else => return .noop,
    }
}

fn deletion(self: *Repl, key: Key) HandlerResult {
    if (key.codepoint == Key.backspace) {
        if (key.mods.ctrl) {
            self.input.buf.deleteWordBefore();
        } else {
            self.input.buf.deleteBeforeCursor();
        }

        return .done;
    }

    if (key.codepoint == Key.delete) {
        if (key.mods.ctrl) {
            self.input.buf.deleteWordAfter();
        } else {
            self.input.buf.deleteAfterCursor();
        }

        return .done;
    }

    return .noop;
}

const handlers: []const *const fn (*Repl, Key) HandlerResult = &.{
    ctrlCombinations,
    arrows,
    deletion,
};
