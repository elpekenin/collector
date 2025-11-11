const std = @import("std");

const tables = @import("../database.zig").tables;

const ptz = @import("ptz");
const sdk = ptz.Sdk(.en);

const database = @import("../database.zig");
const utils = @import("../utils.zig");
const App = @import("../App.zig");

pub fn run(app: *App, reader: *std.Io.Reader, adding: bool) !void {
    const card_id = try utils.takeWord(reader) orelse {
        try app.repl.err(&.{"must provide card's id"}, .{});
        return;
    };

    const variant = try utils.takeWord(reader) orelse {
        try app.repl.err(&.{"must provide variant"}, .{});
        return;
    };

    if (try utils.takeWord(reader)) |_| {
        try app.repl.err(&.{"too many args"}, .{});
        return;
    }

    var diagnostics: database.Diagnostics = undefined;
    const query: database.Owned(?tables.pokemon) = database.get(
        &app.connection,
        .pokemon,
        app.allocator,
        .card_id,
        card_id,
        &diagnostics,
    ) catch |e| {
        try app.stderr.print("{f}\n", .{diagnostics});
        return e;
    };
    defer query.deinit();

    const pokemon = query.value orelse {
        try app.repl.err(
            &.{
                "no card found with id '",
                card_id,
                "', may need to run the 'download' command",
            },
            .{},
        );
        return;
    };

    const available_variants = pokemon.variants.value;
    if (available_variants.isEmpty()) @panic("how is available_variants empty?");

    var owned_variants = utils.getOrCreateOwnedVariants(
        &app.connection,
        app.allocator,
        card_id,
        &diagnostics,
    ) catch |e| {
        try app.stderr.print("{f}\n", .{diagnostics});
        return e;
    };

    const already_owned = owned_variants.get(variant) catch |e| switch (e) {
        error.InvalidFieldName => {
            // TODO: show valid values
            try app.repl.err(&.{ "invalid value for variant: ", variant }, .{});
            return;
        },
    };

    if (already_owned == adding) {
        const msg = if (adding) "already in database" else "not in database";
        try app.repl.warn(&.{ card_id, " (", variant, ") ", msg }, .{});
        return;
    }

    const is_available = available_variants.get(variant) catch |e| switch (e) {
        error.InvalidFieldName => unreachable,
    };
    if (adding and !is_available) {
        try app.repl.err(&.{ "card '", card_id, "' does not have a ", variant, " variant" }, .{});
        return;
    }

    owned_variants.set(variant, adding) catch |e| switch (e) {
        error.InvalidFieldName => unreachable,
    };

    database.save(
        &app.connection,
        .owned,
        app.allocator,
        .{
            .card_id = card_id,
            .variants = .from(owned_variants),
        },
        &diagnostics,
    ) catch |e| {
        try app.stderr.print("{f}\n", .{diagnostics});
        return e;
    };

    const msg = if (adding) "added " else "removed ";
    try app.repl.success(
        &.{
            msg,
            pokemon.name,
            " (",
            card_id,
            ") ",
            variant,
        },
        .{},
    );
}
