const std = @import("std");

const Line = @import("Line.zig");

const History = @This();

pub const Entry = struct {
    is_input: bool,
    line: Line,

    pub const empty: Entry = .{
        .is_input = false,
        .line = .empty,
    };

    pub fn deinit(self: *Entry, allocator: std.mem.Allocator) void {
        self.line.deinit(allocator);
    }
};

cursor: ?usize,
entries: std.ArrayList(Entry),

pub const empty: History = .{
    .cursor = null,
    .entries = .empty,
};

pub fn deinit(self: *History, allocator: std.mem.Allocator) void {
    for (self.entries.items) |*entry| {
        entry.deinit(allocator);
    }

    self.entries.deinit(allocator);
}

pub fn getLen(self: *History) usize {
    return self.entries.items.len;
}

pub fn lastEntry(self: *History) *Entry {
    const len = self.getLen();

    if (len == 0) @panic("oops");
    return &self.entries.items[len - 1];
}

pub fn lastLine(self: *History) *Line {
    return &self.lastEntry().line;
}

pub fn popFirst(self: *History) Entry {
    if (self.cursor) |cursor| {
        if (cursor > 0) self.cursor = cursor - 1;
    }

    return self.entries.orderedRemove(0);
}

fn computeCursor(self: *History) void {
    if (self.cursor) |_| return;

    var index = self.getLen();
    while (index > 0) {
        index -= 1;

        if (self.entries.items[index].is_input) {
            self.cursor = index;
            return;
        }
    }
}

const Direction = enum {
    up,
    down,
};

pub fn getSelectedEntry(self: *History) ?*Entry {
    const cursor = self.cursor orelse return null;
    return &self.entries.items[cursor];
}

fn moveCursor(self: *History, direction: Direction) void {
    if (self.cursor == null) self.computeCursor();

    var index = self.cursor orelse return;

    while (true) {
        switch (direction) {
            .up => {
                if (index == 0) return;
                index -= 1;
            },
            .down => {
                if (index == self.getLen() - 1) return;
                index += 1;
            },
        }

        const entry = &self.entries.items[index];
        if (entry.is_input) {
            self.cursor = index;
            return;
        }
    }
}

pub fn moveCursorUp(self: *History) void {
    self.moveCursor(.up);
}

pub fn moveCursorDown(self: *History) void {
    self.moveCursor(.down);
}
