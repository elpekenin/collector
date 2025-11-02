const std = @import("std");

const cli = @import("cli.zig");
const database = @import("database.zig");
const utils = @import("utils.zig");
const MissingIterator = @import("MissingIterator.zig");

const Context = struct {
    allocator: std.mem.Allocator,
    args: cli.Args,
    repo: database.Repo,
    stderr: *std.Io.Writer,
    stdout: *std.Io.Writer,
};

// const owned: []const []const u8 = &.{
//     "bw10-49",
//     "swsh10-073", // VMAX
//     "swsh11-088",
//     "swsh3.5-26", // has regular and foil
//     "swshp-SWSH243", // Lost Origin Promo
//     "xy3-46",
//     "xy7-90", // EX, bad condition
//     "xyp-XY108", // EX Promo
// };

fn innerMain(ctx: *Context) !u8 {
    switch (ctx.args) {
        .init => {
            try database.createDb(&ctx.repo);
            return 0;
        },
        .ls => |args| {
            const name = args.name orelse {
                try ctx.stderr.print("missing '--name'\n", .{});
                return 1;
            };

            var missing: MissingIterator = try .create(ctx.allocator, &ctx.repo, name);
            defer missing.destroy();

            while (try missing.next()) |card| {
                const pokemon = switch (card) {
                    .pokemon => |pokemon| pokemon,
                    else => {
                        try ctx.stderr.print("found a non-pokemon card\n", .{});
                        return 1;
                    },
                };

                try ctx.stdout.print("{s} {s} - ", .{ pokemon.set.name, pokemon.localId });

                try utils.printPrice(ctx.stdout, pokemon);

                if (pokemon.image) |image| {
                    try ctx.stdout.print(" - {f}", .{image});
                }

                try ctx.stdout.writeByte('\n');
            }
            return 0;
        },
        else => {
            try ctx.stderr.print("this operation is not implemented yet, stay tuned\n", .{});
            return 1;
        },
    }
}

pub fn main() !u8 {
    var stdout_fw: std.fs.File.Writer = .init(.stdout(), &.{});
    const stdout = &stdout_fw.interface;
    defer stdout.flush() catch {};

    var stderr_fw: std.fs.File.Writer = .init(.stderr(), &.{});
    const stderr = &stderr_fw.interface;
    defer stderr.flush() catch {};

    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();

    var arena: std.heap.ArenaAllocator = .init(gpa.allocator());
    defer arena.deinit();

    const allocator = arena.allocator();

    const result = try cli.parseArgs(allocator);
    defer result.deinit();

    const args = result.verb orelse {
        try stderr.print("must specify an operation\n", .{});
        return 1;
    };

    var repo: database.Repo = try .init(allocator, .{
        // default initializer:
        //   - reads user and password from env (JETQUERY_*)
        //   - uses default port (5432)
        //   - sets other params to default values
        .adapter = .{
            .database = "collector",
        },
    });
    defer repo.deinit();

    var ctx: Context = .{
        .allocator = allocator,
        .args = args,
        .repo = repo,
        .stderr = stderr,
        .stdout = stdout,
    };

    return innerMain(&ctx) catch return 1;
}
