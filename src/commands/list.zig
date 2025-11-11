const std = @import("std");

const ptz = @import("ptz");
const sdk = ptz.Sdk(.en);

const database = @import("../database.zig");
const tables = database.tables;

const utils = @import("../utils.zig");
const App = @import("../App.zig");

fn missingVariants(available_variants: ptz.Variants, owned_variants: ptz.Variants) ptz.Variants {
    var missing: ptz.Variants = .empty;

    inline for (@typeInfo(ptz.Variants).@"struct".fields) |field| {
        const is_available = @field(available_variants, field.name);
        const is_owned = @field(owned_variants, field.name);

        if (is_available and !is_owned) {
            @field(missing, field.name) = true;
        }
    }

    return missing;
}

pub fn run(app: *App, reader: *std.Io.Reader, owned: bool) !void {
    const name = try utils.takeWord(reader) orelse {
        try app.repl.err(&.{"must provide Pokemon's name"}, .{});
        return;
    };

    if (try utils.takeWord(reader)) |_| {
        try app.repl.err(&.{"too many args"}, .{});
        return;
    }

    var diagnostics: database.Diagnostics = undefined;
    const query: database.Owned([]const tables.pokemon) = database.all(
        &app.connection,
        .pokemon,
        app.allocator,
        &diagnostics,
    ) catch |e| {
        try app.stderr.print("{f}\n", .{diagnostics});
        return e;
    };
    defer query.deinit();

    const tcgp: sdk.Serie = try .get(app.allocator, .{
        .id = "tcgp",
    });
    defer tcgp.deinit();

    var interrupted, var pokemon_exists, var something_found = .{ false, false, false };
    for (query.value) |pokemon| {
        if (try utils.interruptRequested(&app.repl)) {
            interrupted = true;
            break;
        }

        // do not stale the TUI
        try app.repl.render();

        if (utils.isFromSerie(pokemon.card_id, tcgp)) continue;

        if (std.ascii.indexOfIgnoreCase(pokemon.name, name) == null) continue;
        pokemon_exists = true;

        const available_variants = pokemon.variants.value;
        if (available_variants.isEmpty()) @panic("how is available_variants empty?");

        const owned_variants = utils.getOrCreateOwnedVariants(&app.connection, app.allocator, pokemon.card_id, &diagnostics) catch |e| {
            try app.stderr.print("{f}\n", .{diagnostics});
            return e;
        };

        const variants_to_show = if (owned)
            owned_variants
        else
            missingVariants(available_variants, owned_variants);
        if (variants_to_show.isEmpty()) continue;

        try app.repl.addLine();
        try app.repl.print(&.{
            .{ .text = "[" },
            .{ .text = pokemon.card_id },
            .{ .text = "] " },
            .{ .text = pokemon.name, .link = .{ .uri = pokemon.image_url } },
            .{ .text = " (" },
        });

        var needs_space = false;
        inline for (@typeInfo(ptz.Variants).@"struct".fields) |field| {
            if (@field(variants_to_show, field.name)) {
                defer needs_space = true;

                if (needs_space) {
                    try app.repl.print(&.{
                        .{ .text = " " },
                    });
                }

                try app.repl.print(&.{
                    .{ .text = field.name },
                });
            }
        }

        try app.repl.print(&.{
            .{ .text = ")" },
        });

        something_found = true;
    }

    if (!interrupted and !pokemon_exists) {
        try app.repl.err(&.{ "no information found in database (may need to run 'download ", name, "')" }, .{});
        return;
    }

    if (!interrupted and !something_found) {
        try app.repl.warn(&.{"nothing found"}, .{});
        return;
    }

    try app.repl.promptInNewLine();
}
