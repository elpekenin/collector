const std = @import("std");

const Line = @import("Line.zig");

const History = @This();

pub const Entry = struct {
    input: bool,
    line: Line,

    pub const empty: Entry = .{
        .input = false,
        .line = .empty,
    };

    pub fn deinit(self: *const Entry, allocator: std.mem.Allocator) void {
        self.line.deinit(allocator);
    }
};

entries: std.ArrayList(Entry),

pub const empty: History = .{
    .entries = .empty,
};

pub fn lastEntry(self: *History) *Entry {
    if (self.entries.items.len == 0) @panic("oops");
    return &self.entries.items[self.entries.items.len - 1];
}

pub fn lastLine(self: *History) *Line {
    return &self.lastEntry().line;
}

pub fn popFirst(self: *History) Entry {
    return self.entries.orderedRemove(0);
}
