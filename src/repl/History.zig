const std = @import("std");
const Allocator = std.mem.Allocator;
const DoublyLinkedList = std.DoublyLinkedList;

const History = @This();

pub const Line = struct {
    texts: std.ArrayList([]const u8),
    node: DoublyLinkedList.Node,

    pub fn append(self: *Line, allocator: Allocator, text: []const u8) Allocator.Error![]const u8 {
        const copy = try allocator.dupe(u8, text);
        errdefer allocator.free(copy);

        try self.texts.append(allocator, copy);

        return copy;
    }

    pub fn create(allocator: Allocator) Allocator.Error!*Line {
        const self = try allocator.create(Line);
        self.* = .{ .texts = .empty, .node = .{} };
        return self;
    }

    pub fn destroy(self: *Line, allocator: Allocator) void {
        self.texts.deinit(allocator);
        allocator.free(self);
    }

    pub fn fromNode(node: ?*DoublyLinkedList.Node) ?*Line {
        return if (node) |n|
            @fieldParentPtr("node", n)
        else
            null;
    }
};

lines: std.DoublyLinkedList,

pub const empty: History = .{
    .lines = .{},
};

pub fn addLine(self: *History, allocator: Allocator) Allocator.Error!*Line {
    const line: *Line = try .create(allocator);
    self.lines.append(&line.node);
    return line;
}

pub fn first(self: *History) ?*Line {
    return .fromNode(self.lines.first);
}

pub fn last(self: *History) ?*Line {
    return .fromNode(self.lines.last);
}

pub fn destroyFirst(self: *History, allocator: Allocator) void {
    const line: *Line = .fromNode(self.lines.popFirst()) orelse return;
    line.destroy(allocator);
}

pub fn destroyLast(self: *History, allocator: Allocator) ?*Line {
    const line: *Line = .fromNode(self.lines.pop()) orelse return;
    line.destroy(allocator);
}