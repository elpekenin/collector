const std = @import("std");

const sdk = @import("ptz").Sdk(.en);

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

fn missingArg(stderr: *std.Io.Writer, arg: []const u8) !void {
    try stderr.print("missing argument '--{s}'\n", .{arg});
}

fn notAPokemon(stderr: *std.Io.Writer) !void {
    try stderr.print("found a non-Pokemon card\n", .{});
}

/// Get the Pokemon payload from a Card, otherwise error
fn unwrapPokemon(card: sdk.Card) error{NonPokemonCard}!sdk.Card.Pokemon {
    return switch (card) {
        .pokemon => |pokemon| pokemon,
        else => error.NonPokemonCard,
    };
}

/// Check that this id represents a Pokemon card
fn isPokemon(allocator: std.mem.Allocator, id: []const u8) !bool {
    const card: sdk.Card = try .get(allocator, .{
        .id = id,
    });

    _ = unwrapPokemon(card) catch |e| switch (e) {
        error.NonPokemonCard => return false,
    };

    return true;
}

fn exists(repo: *database.Repo, id: []const u8) !bool {
    const query = repo.Query(.Owned)
        .select()
        .where(.{ .card_id = id })
        .exists();

    return repo.execute(query);
}

fn innerMain(ctx: *Context) !u8 {
    switch (ctx.args) {
        .init => try database.createDb(&ctx.repo),
        .ls => |args| {
            const name = args.name orelse {
                try missingArg(ctx.stderr, "name");
                return 1;
            };

            var missing: MissingIterator = try .create(ctx.allocator, &ctx.repo, name);
            defer missing.destroy();

            while (try missing.next()) |card| {
                const pokemon = unwrapPokemon(card) catch |e| switch (e) {
                    error.NonPokemonCard => {
                        try notAPokemon(ctx.stderr);
                        return 1;
                    },
                    else => return e,
                };

                try ctx.stdout.print("{s} {s} - ", .{ pokemon.set.name, pokemon.localId });

                try utils.printPrice(ctx.stdout, pokemon);

                if (pokemon.image) |image| {
                    try ctx.stdout.print(" - {f}", .{image});
                }

                try ctx.stdout.writeByte('\n');
            }
        },
        .add => |args| {
            const id = args.id orelse {
                try missingArg(ctx.stderr, "id");
                return 1;
            };

            if (!try isPokemon(ctx.allocator, id)) {
                try notAPokemon(ctx.stderr);
                return 1;
            }

            // TODO: check it doesn't exist already
            const query = ctx.repo.Query(.Owned)
                .insert(.{ .card_id = id });

            try ctx.repo.execute(query);

            try ctx.stdout.print("added '{s}' to database\n", .{id});
        },
        .rm => |args| {
            const id = args.id orelse {
                try missingArg(ctx.stderr, "id");
                return 1;
            };

            if (!try isPokemon(ctx.allocator, id)) {
                try notAPokemon(ctx.stderr);
                return 1;
            }

            // TODO: check it already exists
            const query = ctx.repo.Query(.Owned)
                .delete()
                .where(.{ .card_id = id });

            try ctx.repo.execute(query);

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

    return innerMain(&ctx);
}
