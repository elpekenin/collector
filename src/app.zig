//! Interact with the database in a REPL

const std = @import("std");

const sdk = @import("ptz").Sdk(.en);

const vaxis = @import("vaxis");
const Input = vaxis.widgets.TextInput;

const db = @import("db.zig");
const Ctx = @import("Ctx.zig");
const Owned = @import("Owned.zig");
const Repl = @import("repl/Repl.zig");

const Variant = Owned.VariantEnum;

const Command = enum {
    @"?",
    db,
    exit,

    add,
    rm,

    owned,
    missing,
};

fn isFromSerie(brief: sdk.Card.Brief, serie: sdk.Serie) bool {
    for (serie.sets) |set| {
        if (std.mem.startsWith(u8, brief.id, set.id)) {
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

fn variantExists(pokemon: sdk.Card.Pokemon, variant: Variant) bool {
    return switch (variant) {
        .normal => pokemon.variants.normal,
        .reverse => pokemon.variants.reverse,
        .holo => pokemon.variants.holo,
        .firstEdition => pokemon.variants.firstEdition,
    };
}

pub fn run(ctx: *Ctx) !u8 {
    var buffer: [1024]u8 = undefined;

    var repl: Repl = .create(ctx.allocator);
    try repl.init(&buffer);

    defer repl.destroy();

    while (true) {
        try repl.render();

        const event = try repl.nextEvent() orelse continue;

        const line = switch (event) {
            .exit => |code| return code,
            .input => |line| line,
        };

        defer repl.allocator.free(line);
        try repl.storeInput(line);

        var r: std.Io.Reader = .fixed(line);
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
            .@"?" => {
                if (try takeWord(reader)) |_| {
                    try repl.err(&.{"too many args"});
                    continue;
                }

                try repl.printInNewLine(&.{
                    .{ .text = "available commands:" },
                });

                inline for (@typeInfo(Command).@"enum".fields) |field| {
                    try repl.print(&.{
                        .{ .text = " " },
                        .{ .text = field.name },
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
                    .{ .text = std.mem.sliceTo(db.filename(&ctx.conn), 0) },
                });

                try repl.newPrompt();
            },

            .exit => {
                if (try takeWord(reader)) |_| {
                    try repl.err(&.{"too many args"});
                    continue;
                }

                return 0;
            },

            .missing,
            .owned,
            => {
                const owned = command == .owned;

                const name = try takeWord(reader) orelse {
                    try repl.err(&.{"missing Pokemon's name"});
                    continue;
                };

                if (try takeWord(reader)) |_| {
                    try repl.err(&.{"too many args"});
                    continue;
                }

                const tcgp: sdk.Serie = try .get(ctx.allocator, .{
                    .id = "tcgp",
                });

                var iterator = sdk.Card.Brief.iterator(ctx.allocator, .{
                    .where = &.{
                        .like(.name, name),
                    },
                });

                // used for image links, so that text lives enough to be rendered
                var arena: std.heap.ArenaAllocator = .init(ctx.allocator);
                defer arena.deinit();

                var empty = true;

                iterator_loop: while (try iterator.next()) |briefs| {
                    card_loop: for (briefs) |brief| {
                        if (isFromSerie(brief, tcgp)) continue;

                        for (std.enums.values(Variant)) |variant| {
                            // allow to break loop with Ctrl+C
                            if (repl.loop.tryEvent()) |evt| {
                                switch (evt) {
                                    // NOTE: this will drop some input, but we can live with it
                                    .key_press => |key| {
                                        if (key.mods.ctrl and key.codepoint == 'c') {
                                            try repl.printInNewLine(&.{
                                                .{ .text = "interrupted" },
                                            });

                                            break :iterator_loop;
                                        }
                                    },
                                    // re-publish event for later consumption
                                    else => repl.loop.postEvent(evt),
                                }
                            }

                            if (try db.isOwned(&ctx.conn, brief.id, variant) != owned) continue;

                            const card: sdk.Card = try .get(ctx.allocator, .{
                                .id = brief.id,
                            });

                            const pokemon = switch (card) {
                                .pokemon => |pokemon| if (variantExists(pokemon, variant))
                                    pokemon
                                else
                                    continue,
                                else => {
                                    try repl.warn(&.{"found a non-pokemon card"});
                                    continue :card_loop;
                                },
                            };

                            empty = false;

                            var allocating: std.Io.Writer.Allocating = .init(arena.allocator());
                            const writer = &allocating.writer;

                            const link: vaxis.Cell.Hyperlink = if (pokemon.image) |image| link: {
                                try image.toUrl(writer, .high, .jpg);
                                break :link .{ .uri = try allocating.toOwnedSlice() };
                            } else .{};

                            try repl.addLine();
                            try repl.print(&.{
                                .{ .text = "[" },
                                .{ .text = pokemon.id },
                                .{ .text = "] " },
                                .{ .text = pokemon.name, .link = link },
                                .{ .text = " (" },
                                .{ .text = @tagName(variant) },
                                .{ .text = ") " },
                            });

                            // render on each card, so that screen is not frozen
                            try repl.render();
                        }
                    }
                }

                if (empty) {
                    try repl.warn(&.{"nothing found"});
                    continue;
                }

                try repl.newPrompt();
            },

            .add,
            .rm,
            => {
                const adding = command == .add;

                const id = try takeWord(reader) orelse {
                    try repl.err(&.{"missing card's id"});
                    continue;
                };

                const variant_raw = try takeWord(reader) orelse {
                    try repl.err(&.{"missing variant"});
                    continue;
                };

                const variant = std.meta.stringToEnum(Variant, variant_raw) orelse {
                    const variants = comptime std.enums.values(Variant);
                    var buf: [variants.len * 2 + 1][]const u8 = @splat(" ");

                    buf[0] = "invalid variant value, options are: ";

                    for (variants, 0..) |variant, i| {
                        buf[i * 2 + 1] = @tagName(variant);
                    }

                    try repl.err(&buf);
                    continue;
                };

                if (try takeWord(reader)) |_| {
                    try repl.err(&.{"too many args"});
                    continue;
                }

                if (try db.isOwned(&ctx.conn, id, variant) == adding) {
                    const msg = if (adding) "already in database" else "not in database";
                    try repl.warn(&.{msg});
                    continue;
                }

                const card = sdk.Card.get(ctx.allocator, .{
                    .id = id,
                }) catch |e| switch (e) {
                    // not a card
                    error.ServerErrorStatus => {
                        try repl.err(&.{"id does not exist"});
                        continue;
                    },
                    else => return e,
                };
                defer card.free(ctx.allocator);

                const pokemon = switch (card) {
                    .pokemon => |pokemon| if (variantExists(pokemon, variant))
                        pokemon
                    else {
                        try repl.err(&.{ pokemon.name, "(", id, ") has no ", variant_raw, " variant" });
                        continue;
                    },
                    else => {
                        try repl.err(&.{"card is not a pokemon"});
                        continue;
                    },
                };

                if (adding) {
                    try db.addOwned(&ctx.conn, id, variant);
                } else {
                    try db.rmOwned(&ctx.conn, id, variant);
                }

                const msg = if (adding) "added " else "removed ";
                try repl.success(&.{ msg, pokemon.name, " (", id, ") ", variant_raw });
            },
        }
    }
}
