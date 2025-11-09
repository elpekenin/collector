// TODO: accross the project, properly handle resources (missing `errdefer allocator.free()` and the like)
//       doesn't matter atm because errors propagate (program quits), could become a problem if we recover from them

const std = @import("std");

const sdk = @import("ptz").Sdk(.en);

const app = @import("app.zig");
const Ctx = @import("Ctx.zig");
const Database = @import("Database.zig");

fn missingArg(stderr: *std.Io.Writer, arg: []const u8) !void {
    try stderr.print("error: missing argument '--{s}'\n", .{arg});
}

pub fn main() !u8 {
    var stdout_fw: std.fs.File.Writer = .init(.stdout(), &.{});
    const stdout = &stdout_fw.interface;
    defer stdout.flush() catch {};

    var stderr_fw: std.fs.File.Writer = .init(.stderr(), &.{});
    const stderr = &stderr_fw.interface;
    defer stderr.flush() catch {};

    // TODO: find some other (faster) allocator to use
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    // validate arguments
    {
        var args: std.process.ArgIterator = try .initWithAllocator(allocator);
        defer args.deinit();

        if (!args.skip()) {
            try stderr.print("program's name was expected\n", .{});
            return 1;
        }

        if (args.skip()) {
            try stderr.print("this program doesn't receive arguments\n", .{});
            return 1;
        }
    }

    const dir_path = try std.fs.getAppDataDir(allocator, "collector");
    defer allocator.free(dir_path);

    // check if folder exists, otherwise create it
    {
        const absolute_path = try std.fs.path.resolve(allocator, &.{dir_path});
        defer allocator.free(absolute_path);

        std.fs.accessAbsolute(absolute_path, .{}) catch |e| switch (e) {
            error.FileNotFound => {
                try std.fs.makeDirAbsolute(absolute_path);
                try stdout.print("info: created directory '{s}' for data storage\n", .{absolute_path});
            },
            else => return e,
        };
    }

    const path = try std.fs.path.joinZ(allocator, &.{ dir_path, "db.sqlite3" });
    defer allocator.free(path);

    var database = try Database.init(allocator, stderr, path);
    defer database.deinit();

    var ctx: Ctx = .{
        .allocator = allocator,
        .database = &database,
        .stderr = stderr,
        .stdout = stdout,
    };

    return app.run(&ctx);
}
