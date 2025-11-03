const std = @import("std");

const args = @import("args");

const Void = struct {};

// TODO: support multiple ids in add/rm?

pub const Args = union(enum) {
    const Add = struct {
        id: ?[]const u8 = null,
    };

    const Rm = struct {
        id: ?[]const u8 = null,
    };

    const Ls = struct {
        name: ?[]const u8 = null,
    };

    init,
    ls: Ls,
    add: Add,
    rm: Rm,
};

pub fn parseArgs(allocator: std.mem.Allocator) !args.ParseArgsResult(Void, Args) {
    var args_it: std.process.ArgIterator = try .initWithAllocator(allocator);
    defer args_it.deinit();

    std.debug.assert(args_it.skip()); // skip exe name

    return args.parseWithVerb(Void, Args, &args_it, allocator, .print);
}
