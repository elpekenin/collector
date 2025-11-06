const std = @import("std");
const Allocator = std.mem.Allocator;

const vaxis = @import("vaxis");

const Line = @This();

segments: std.ArrayList(vaxis.Segment),

pub const empty: Line = .{ .segments = .empty };

/// copies all texts to make sure we don't draw dangling pointers
pub fn append(self: *Line, allocator: Allocator, segment: vaxis.Segment) Allocator.Error!void {
    const seg = try allocator.create(vaxis.Segment);
    seg.* = .{
        .text = try allocator.dupe(u8, segment.text),
        .style = segment.style,
        .link = .{
            .uri = try allocator.dupe(u8, segment.link.uri),
            .params = try allocator.dupe(u8, segment.link.params),
        },
    };

    try self.segments.append(allocator, seg.*);
}

pub fn appendSlice(self: *Line, allocator: Allocator, segments: []const vaxis.Segment) Allocator.Error!void {
    for (segments) |segment| {
        try self.append(allocator, segment);
    }
}

/// append all the texts into a single string, any styling will be lost
pub fn toOwnedSlice(self: *const Line, allocator: Allocator) Allocator.Error![]const u8 {
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(allocator);

    for (self.segments.items) |segment| {
        try list.appendSlice(allocator, segment.text);
    }

    return list.toOwnedSlice(allocator);
}

pub fn deinit(self: *const Line, allocator: Allocator) void {
    for (self.segments.items) |item| {
        allocator.free(item.text);
        allocator.free(item.link.uri);
        allocator.free(item.link.params);
    }
}
