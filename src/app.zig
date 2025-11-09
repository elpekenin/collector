//! Interact with the database in a REPL

const std = @import("std");

const ptz = @import("ptz");
const sdk = ptz.Sdk(.en);

const vaxis = @import("vaxis");
const Input = vaxis.widgets.TextInput;

const Ctx = @import("Ctx.zig");

const Database = @import("Database.zig");
const tables = Database.tables;

const Repl = @import("repl/Repl.zig");
const styles = Repl.styles;

pub fn run(ctx: *Ctx) !u8 {
    var buffer: [1024]u8 = undefined;

    var repl: Repl = .create(ctx.allocator);
    try repl.init(&buffer);

    defer repl.deinit();

    while (true) {
        try repl.render();

        const event = try repl.nextEvent() orelse continue;

        const input = switch (event) {
            .exit => |code| return code,
            .input => |input| input,
        };

        defer repl.allocator.free(input);
        try repl.storeInput(input);

        var r: std.Io.Reader = .fixed(input);
        const reader = &r;

        // on empty line, do nothing
        const str = try takeWord(reader) orelse {
            try repl.newPrompt();
            continue;
        };

        const command = std.meta.stringToEnum(Command, str) orelse {
            try repl.err(&.{ "unknown command: ", str });
            continue;
        };

        switch (command) {
            .exit => {
                if (try takeWord(reader)) |_| {
                    try repl.err(&.{"too many args"});
                    continue;
                }

                return 0;
            },

            .help => {
                if (try takeWord(reader)) |_| {
                    try repl.err(&.{"too many args"});
                    continue;
                }

                try repl.printInNewLine(&.{
                    .{ .text = "available commands:" },
                });

                for (std.enums.values(Command)) |cmd| {
                    // prevent help from listing itself
                    if (cmd == .help) continue;

                    try repl.print(&.{
                        .{ .text = " " },
                        .{ .text = @tagName(cmd) },
                    });
                }

                try repl.newPrompt();
            },

            .db => {
                if (try takeWord(reader)) |_| {
                    try repl.err(&.{"too many args"});
                    continue;
                }

                try repl.printInNewLine(&.{
                    .{ .text = "database stored at: " },
                    .{ .text = std.mem.sliceTo(ctx.database.getFilename(), 0) },
                });

                try repl.newPrompt();
            },

            .download => {
                const name = try takeWord(reader) orelse "";

                if (try takeWord(reader)) |_| {
                    try repl.err(&.{"too many args"});
                    continue;
                }

                const tcgp: sdk.Serie = try .get(ctx.allocator, .{
                    .id = "tcgp",
                });
                defer tcgp.deinit();

                var iterator = sdk.Card.Brief.iterator(ctx.allocator, .{
                    .where = &.{
                        .like(.name, name),
                    },
                });

                var interrupted, var pokemon_exists = .{ false, false };
                briefs_loop: while (try iterator.next()) |briefs| {
                    defer briefs[briefs.len - 1].deinit();

                    pokemon_exists = true;

                    for (briefs) |brief| {
                        if (try interruptRequested(&repl)) {
                            interrupted = true;
                            break :briefs_loop;
                        }

                        if (isFromSerie(brief.id, tcgp)) continue;

                        const card: sdk.Card = try .get(ctx.allocator, .{
                            .id = brief.id,
                        });
                        defer card.deinit();

                        const pokemon = switch (card) {
                            .pokemon => |pokemon| pokemon,
                            else => {
                                try repl.warn(&.{"found a non-pokemon card, ignoring it"});
                                continue;
                            },
                        };

                        if (pokemon.variants.isEmpty()) {
                            try repl.printInNewLine(&.{
                                .{ .text = "there are no defined variants for '", .style = styles.red },
                                .{ .text = pokemon.id, .style = styles.red },
                                .{ .text = "', skipping it", .style = styles.red },
                            });
                            continue;
                        }

                        var allocating: std.Io.Writer.Allocating = .init(ctx.allocator);
                        defer allocating.deinit();

                        if (pokemon.image) |image| {
                            try image.format(&allocating.writer);
                        }

                        const url = try allocating.toOwnedSlice();
                        defer ctx.allocator.free(url);

                        try ctx.database.save(.pokemon, ctx.allocator, .{
                            .card_id = pokemon.id,
                            .name = pokemon.name,
                            .image_url = url,
                            .variants = .from(pokemon.variants),
                        });

                        try repl.printInNewLine(&.{
                            .{ .text = "[" },
                            .{ .text = pokemon.id },
                            .{ .text = "] " },
                            .{ .text = pokemon.name },
                        });

                        try repl.render();
                    }
                }

                if (!interrupted and !pokemon_exists) {
                    try repl.err(&.{
                        "there are no Pokemon cards with '",
                        name,
                        "' in their name",
                    });
                    continue;
                }

                try repl.newPrompt();
            },

            .missing,
            .owned,
            => {
                const listing_owned = command == .owned;

                const name = try takeWord(reader) orelse {
                    try repl.err(&.{"must provide Pokemon's name"});
                    continue;
                };

                if (try takeWord(reader)) |_| {
                    try repl.err(&.{"too many args"});
                    continue;
                }

                const query = try ctx.database.all(.pokemon, ctx.allocator);
                defer query.deinit();

                const pokemons: []const tables.pokemon = query.value;

                const tcgp: sdk.Serie = try .get(ctx.allocator, .{
                    .id = "tcgp",
                });
                defer tcgp.deinit();

                var interrupted, var pokemon_exists, var something_found = .{ false, false, false };
                for (pokemons) |pokemon| {
                    if (try interruptRequested(&repl)) {
                        interrupted = true;
                        break;
                    }
                    if (isFromSerie(pokemon.card_id, tcgp)) continue;

                    if (std.ascii.indexOfIgnoreCase(pokemon.name, name) == null) continue;
                    pokemon_exists = true;

                    const available_variants = pokemon.variants.value;
                    if (available_variants.isEmpty()) @panic("how is available_variants empty?");

                    const owned_variants = try getOrCreateOwnedVariants(ctx.allocator, ctx.database, pokemon.card_id);

                    const variants_to_show = if (listing_owned)
                        owned_variants
                    else
                        missingVariants(available_variants, owned_variants);
                    if (variants_to_show.isEmpty()) continue;

                    try repl.addLine();
                    try repl.print(&.{
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
                                try repl.print(&.{
                                    .{ .text = " " },
                                });
                            }

                            try repl.print(&.{
                                .{ .text = field.name },
                            });
                        }
                    }

                    try repl.print(&.{
                        .{ .text = ")" },
                    });

                    try repl.render();

                    something_found = true;
                }

                if (!interrupted and !pokemon_exists) {
                    try repl.err(&.{
                        "no information found in database (may need to run 'download ",
                        name,
                        "')",
                    });
                    continue;
                }

                if (!interrupted and !something_found) {
                    try repl.warn(&.{"nothing found"});
                    continue;
                }

                try repl.newPrompt();
            },

            // FIXME: implement using update instead of add/rm
            .add,
            .rm,
            => {
                const adding = command == .add;

                const card_id = try takeWord(reader) orelse {
                    try repl.err(&.{"must provide card's id"});
                    continue;
                };

                const variant = try takeWord(reader) orelse {
                    try repl.err(&.{"must provide variant"});
                    continue;
                };

                if (try takeWord(reader)) |_| {
                    try repl.err(&.{"too many args"});
                    continue;
                }

                const query = try ctx.database.get(.pokemon, ctx.allocator, .card_id, card_id);
                defer query.deinit();

                const pokemon: tables.pokemon = query.value orelse {
                    try repl.err(&.{ "no card found with id '", card_id, "'" });
                    continue;
                };

                const available_variants = pokemon.variants.value;
                if (available_variants.isEmpty()) @panic("how is available_variants empty?");

                var owned_variants = try getOrCreateOwnedVariants(ctx.allocator, ctx.database, card_id);
                const already_owned = owned_variants.get(variant) catch |e| switch (e) {
                    error.InvalidFieldName => {
                        // TODO: show valid values
                        try repl.err(&.{ "invalid value for variant: ", variant });
                        continue;
                    },
                };

                if (already_owned == adding) {
                    const msg = if (adding) "already in database" else "not in database";
                    try repl.warn(&.{
                        card_id,
                        " (",
                        variant,
                        ") ",
                        msg,
                    });
                    continue;
                }

                const is_available = available_variants.get(variant) catch |e| switch (e) {
                    error.InvalidFieldName => unreachable,
                };
                if (adding and !is_available) {
                    try repl.err(&.{ "card '", card_id, "' does not have a ", variant, " variant" });
                    continue;
                }

                owned_variants.set(variant, adding) catch |e| switch (e) {
                    error.InvalidFieldName => unreachable,
                };

                try ctx.database.save(.owned, ctx.allocator, .{
                    .card_id = card_id,
                    .variants = .from(owned_variants),
                });
                const msg = if (adding) "added " else "removed ";
                try repl.success(&.{ msg, pokemon.name, " (", card_id, ") ", variant });
            },
        }
    }
}

const Command = enum {
    exit, // end program
    help, // list available commands
    db, // display path of sqlite file
    download, // download info from API into DB

    // manage owned cards
    add,
    rm,

    // show owned cards
    owned,
    missing,
};

fn isFromSerie(card_id: []const u8, serie: sdk.Serie) bool {
    for (serie.sets) |set| {
        if (std.mem.startsWith(u8, card_id, set.id)) {
            return true;
        }
    }

    return false;
}

fn takeWord(reader: *std.Io.Reader) !?[]const u8 {
    while (true) {
        const word = try reader.takeDelimiter(' ') orelse return null;

        if (word.len > 0) {
            return word;
        }
    }
}

fn interruptRequested(repl: *Repl) !bool {
    if (repl.loop.tryEvent()) |evt| {
        switch (evt) {
            // NOTE: this will drop some input, but we can live with it
            .key_press => |key| {
                if (key.mods.ctrl and key.codepoint == 'c') {
                    try repl.printInNewLine(&.{
                        .{ .text = "--- interrupted ---" },
                    });

                    return true;
                }
            },
            // re-publish event for later consumption
            else => repl.loop.postEvent(evt),
        }
    }

    return false;
}

fn getAvailableVariants(pokemon: tables.pokemon) ptz.Variants {
    return pokemon.variants.value;
}

fn getOrCreateOwnedVariants(allocator: std.mem.Allocator, database: *Database, card_id: []const u8) !ptz.Variants {
    const query = try database.get(.owned, allocator, .card_id, card_id);
    defer query.deinit();

    const data: ?tables.owned = query.value;
    if (data) |owned| return owned.variants.value;

    const default: ptz.Variants = .empty;

    try database.save(.owned, allocator, .{
        .card_id = card_id,
        .variants = .from(default),
    });

    return default;
}

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
