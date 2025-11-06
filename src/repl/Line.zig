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

pub fn deinit(self: *const Line, allocator: Allocator) void {
    for (self.segments.items) |item| {
        allocator.free(item.text);
        allocator.free(item.link.uri);
        allocator.free(item.link.params);
    }
}
