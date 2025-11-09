const std = @import("std");
const Allocator = std.mem.Allocator;

const vaxis = @import("vaxis");

const Line = @This();

segments: std.ArrayList(vaxis.Segment),

pub const empty: Line = .{
    .segments = .empty,
};

/// copies all texts to make sure we don't draw dangling pointers
pub fn append(self: *Line, allocator: Allocator, segment: vaxis.Segment) Allocator.Error!void {
    const text = try allocator.dupe(u8, segment.text);
    errdefer allocator.free(text);

    const uri = try allocator.dupe(u8, segment.link.uri);
    errdefer allocator.free(uri);

    const params = try allocator.dupe(u8, segment.link.params);
    errdefer allocator.free(params);

    try self.segments.append(allocator, .{
        .text = text,
        .style = segment.style,
        .link = .{
            .uri = uri,
            .params = params,
        },
    });
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

pub fn deinit(self: *Line, allocator: Allocator) void {
    for (self.segments.items) |segment| {
        allocator.free(segment.text);
        allocator.free(segment.link.uri);
        allocator.free(segment.link.params);
    }

    self.segments.deinit(allocator);
}
