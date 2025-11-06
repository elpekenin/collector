const std = @import("std");

const sdk = @import("ptz").Sdk(.en);

const db = @import("db.zig");
const app = @import("app.zig");
const Ctx = @import("Ctx.zig");

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

    // TODO: find and fix leaks, rather than using an arena
    var arena: std.heap.ArenaAllocator = .init(gpa.allocator());
    defer arena.deinit();

    const allocator = arena.allocator();

    const dir_path = try std.fs.getAppDataDir(allocator, "collector");
    defer allocator.free(dir_path);

    const absolute_path = try std.fs.path.resolve(allocator, &.{dir_path});
    defer allocator.free(absolute_path);

    std.fs.accessAbsolute(absolute_path, .{}) catch |e| switch (e) {
        error.FileNotFound => {
            try std.fs.makeDirAbsolute(absolute_path);
            try stdout.print("info: created directory '{s}' for data storage\n", .{absolute_path});
        },
        else => return e,
    };

    const path = try std.fs.path.joinZ(allocator, &.{ dir_path, "db.sqlite3" });
    defer allocator.free(path);

    const conn = try db.connect(.{
        .path = path,
    });
    defer conn.close();

    var ctx: Ctx = .{
        .allocator = allocator,
        .conn = conn,
        .stderr = stderr,
        .stdout = stdout,
    };

    return app.run(&ctx);
}
