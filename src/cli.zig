const std = @import("std");

const args = @import("args");

// TODO: support multiple ids in add/rm?

const Generic = struct {
    /// location where the database file will be stored
    db_dir: ?[:0]const u8 = null,
};

pub const Command = union(enum) {
    const Add = struct {
        id: ?[]const u8 = null,
    };

    const Rm = struct {
        id: ?[]const u8 = null,
    };

    const Ls = struct {
        name: ?[]const u8 = null,
    };

    ls: Ls,
    add: Add,
    rm: Rm,
};

const Args = args.ParseArgsResult(Generic, Command);

pub fn parseArgs(allocator: std.mem.Allocator) !Args {
    var args_it: std.process.ArgIterator = try .initWithAllocator(allocator);
    defer args_it.deinit();

    std.debug.assert(args_it.skip()); // skip exe name

    return args.parseWithVerb(Generic, Command, &args_it, allocator, .print);
}
