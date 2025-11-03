const std = @import("std");

const sdk = @import("ptz").Sdk(.en);

const cli = @import("cli.zig");
const database = @import("database.zig");
const MissingIterator = @import("MissingIterator.zig");

const Query = database.Query;

const Context = struct {
    allocator: std.mem.Allocator,
    args: cli.Args,
    repo: database.Repo,
    stderr: *std.Io.Writer,
    stdout: *std.Io.Writer,
};

const Error = error{NonPokemonCard};

fn missingArg(stderr: *std.Io.Writer, arg: []const u8) !void {
    try stderr.print("missing argument '--{s}'\n", .{arg});
}

/// Get the Pokemon payload from a Card, otherwise error
fn unwrapPokemon(card: sdk.Card) Error!sdk.Card.Pokemon {
    return switch (card) {
        .pokemon => |pokemon| pokemon,
        else => error.NonPokemonCard,
    };
}

/// Check that this id represents a Pokemon card
fn validateCardId(allocator: std.mem.Allocator, stderr: *std.Io.Writer, id: []const u8) !void {
    const card = sdk.Card.get(allocator, .{
        .id = id,
    }) catch |e| switch (e) {
        error.ServerErrorStatus => {
            try stderr.print("card '{s}' does not exist\n", .{id});
            return error.NotACard;
        },
        else => return e,
    };
    defer card.free(allocator);

    _ = unwrapPokemon(card) catch |e| switch (e) {
        error.NonPokemonCard => {
            try stderr.print("card '{s}' is not a Pokemon\n", .{id});
            return e;
        },
    };
}

fn exists(repo: *database.Repo, id: []const u8) !bool {
    const result = try Query(.Owned)
        .findBy(.{ .card_id = id })
        .execute(repo);
    defer repo.free(result);

    return if (result) |_|
        true
    else
        false;
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
    switch (ctx.args) {
        .init => try database.createDb(&ctx.repo),
        .ls => |args| {
            const name = args.name orelse {
                try missingArg(ctx.stderr, "name");
                return 1;
            };

            var missing: MissingIterator = try .create(ctx.allocator, &ctx.repo, .{
                .where = &.{
                    .like(.name, name),
                }
            });
            defer missing.destroy();

            while (try missing.next()) |card| {
                const pokemon = unwrapPokemon(card) catch |e| switch (e) {
                    error.NonPokemonCard => {
                        try ctx.stderr.print("found a non-Pokemon card\n", .{});
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

            if (try exists(&ctx.repo, id)) {
                try ctx.stderr.print("card '{s}' already owned\n", .{id});
                return 1;
            }

            validateCardId(ctx.allocator, ctx.stderr, id) catch |e| switch (e) {
                error.NotACard,
                error.NonPokemonCard,
                => return 1,
                else => return e,
            };

            try Query(.Owned)
                .insert(.{ .card_id = id })
                .execute(&ctx.repo);

            try ctx.stdout.print("added '{s}' to database\n", .{id});
        },
        .rm => |args| {
            const id = args.id orelse {
                try missingArg(ctx.stderr, "id");
                return 1;
            };

            if (!try exists(&ctx.repo, id)) {
                try ctx.stderr.print("card '{s}' is not owned\n", .{id});
                return 1;
            }

            validateCardId(ctx.allocator, ctx.stderr, id) catch |e| switch (e) {
                error.NotACard,
                error.NonPokemonCard,
                => return 1,
                else => return e,
            };

            try Query(.Owned)
                .delete()
                .where(.{ .card_id = id })
                .execute(&ctx.repo);

            try ctx.stdout.print("removed '{s}' from database\n", .{id});
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

    const args = result.verb orelse {
        try stderr.print("must specify an operation\n", .{});
        return 1;
    };

    var repo = try database.initRepo(allocator);
    defer repo.deinit();

    var ctx: Context = .{
        .allocator = allocator,
        .args = args,
        .repo = repo,
        .stderr = stderr,
        .stdout = stdout,
    };

    return innerMain(&ctx);
}
