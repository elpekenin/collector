const std = @import("std");

const sdk = @import("ptz").Sdk(.en);

const cli = @import("cli.zig");
const db = @import("db.zig");
const MissingIterator = @import("MissingIterator.zig");

const Context = struct {
    allocator: std.mem.Allocator,
    command: cli.Command,
    conn: db.Connection,
    stderr: *std.Io.Writer,
    stdout: *std.Io.Writer,
};

const Error = error{
    NonPokemonCard,
};

fn missingArg(stderr: *std.Io.Writer, arg: []const u8) !void {
    try stderr.print("error: missing argument '--{s}'\n", .{arg});
}

/// Get the Pokemon payload from a Card, otherwise error
fn unwrapPokemon(card: sdk.Card) Error!sdk.Card.Pokemon {
    return switch (card) {
        .pokemon => |pokemon| pokemon,
        else => error.NonPokemonCard,
    };
}

fn validateCardId(allocator: std.mem.Allocator, stderr: *std.Io.Writer, id: []const u8) !void {
    const card = sdk.Card.get(allocator, .{
        .id = id,
    }) catch |e| switch (e) {
        error.ServerErrorStatus => {
            try stderr.print("error: card '{s}' does not exist\n", .{id});
            return error.NotACard;
        },
        else => return e,
    };
    defer card.free(allocator);

    _ = unwrapPokemon(card) catch |e| switch (e) {
        error.NonPokemonCard => {
            try stderr.print("error: card '{s}' is not a Pokemon\n", .{id});
            return e;
        },
    };
}

fn printPrice(writer: *std.Io.Writer, pricing: sdk.Pricing) !bool {
    const cardmarket = if (pricing.cardmarket) |cardmarket|
        cardmarket
    else
        return false;

    if (cardmarket.trend) |trend| {
        try writer.print("{d}", .{trend});
    } else {
        try writer.print("???", .{});
    }

    try writer.print("{s}", .{cardmarket.unit orelse ""});

    return true;
}

fn innerMain(ctx: *Context) !u8 {
    switch (ctx.command) {
        .ls => |args| {
            const name = args.name orelse {
                try missingArg(ctx.stderr, "name");
                return 1;
            };

            var missing: MissingIterator = try .create(ctx.allocator, &ctx.conn, .{
                .where = &.{
                    .like(.name, name),
                },
            });
            defer missing.destroy();

            while (try missing.next()) |card| {
                const pokemon = unwrapPokemon(card) catch |e| switch (e) {
                    error.NonPokemonCard => {
                        try ctx.stderr.print("error: found a non-Pokemon card\n", .{});
                        return 1;
                    },
                    else => return e,
                };

                try ctx.stdout.print("{s} ({s} {s}) [{s}] - ", .{
                    pokemon.name,
                    pokemon.set.name,
                    pokemon.localId,
                    pokemon.id,
                });

                if (pokemon.pricing) |pricing| {
                    if (try printPrice(ctx.stdout, pricing)) {
                        try ctx.stdout.print(" - ", .{});
                    }
                }

                if (pokemon.image) |image| {
                    try ctx.stdout.print("{f}", .{image});
                }

                try ctx.stdout.writeByte('\n');
            }
        },
        .add => |args| {
            const id = args.id orelse {
                try missingArg(ctx.stderr, "id");
                return 1;
            };

            if (try db.isOwned(&ctx.conn, id)) {
                try ctx.stderr.print("warn: card '{s}' already owned\n", .{id});
                return 1;
            }

            validateCardId(ctx.allocator, ctx.stderr, id) catch |e| switch (e) {
                error.NotACard,
                error.NonPokemonCard,
                => return 1,
                else => return e,
            };

            try db.addOwned(&ctx.conn, id);

            try ctx.stdout.print("added '{s}' to database\n", .{id});
        },
        .rm => |args| {
            const id = args.id orelse {
                try missingArg(ctx.stderr, "id");
                return 1;
            };

            if (!try db.isOwned(&ctx.conn, id)) {
                try ctx.stderr.print("warn: card '{s}' is not owned\n", .{id});
                return 1;
            }

            validateCardId(ctx.allocator, ctx.stderr, id) catch |e| switch (e) {
                error.NotACard,
                error.NonPokemonCard,
                => return 1,
                else => return e,
            };

            try db.removeOwned(&ctx.conn, id);

            try ctx.stdout.print("info: removed '{s}' from database\n", .{id});
        },
    }

    return 0;
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

    const result = try cli.parseArgs(allocator);
    defer result.deinit();

    const command = result.verb orelse {
        try stderr.print("error: must specify a command\n", .{});
        return 1;
    };

    // allow user to use a custom directory (or default to OS-specific data dir)
    // however, the filename is hardcoded
    const dir_path: []const u8, const needs_free = if (result.options.db_dir) |dir|
        .{ dir, false }
    else
        .{ try std.fs.getAppDataDir(allocator, "collector"), true };

    defer if (needs_free) allocator.free(dir_path);

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

    try stdout.print("debug: database at '{s}'\n", .{path});

    var ctx: Context = .{
        .allocator = allocator,
        .conn = conn,
        .command = command,
        .stderr = stderr,
        .stdout = stdout,
    };

    return innerMain(&ctx);
}
