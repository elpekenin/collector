const std = @import("std");

const ptz = @import("ptz");
const sdk = ptz.Sdk(.en);

const database = @import("database.zig");
const tables = database.tables;

const Repl = @import("Repl.zig");

pub fn interruptRequested(repl: *Repl) !bool {
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

pub fn takeWord(reader: *std.Io.Reader) !?[]const u8 {
    while (true) {
        const word = try reader.takeDelimiter(' ') orelse return null;

        if (word.len > 0) {
            return word;
        }
    }
}

pub fn isFromSerie(card_id: []const u8, serie: sdk.Serie) bool {
    for (serie.sets) |set| {
        if (std.mem.startsWith(u8, card_id, set.id)) {
            return true;
        }
    }

    return false;
}

pub fn getOrCreateOwnedVariants(
    connection: *database.Connection,
    allocator: std.mem.Allocator,
    card_id: []const u8,
    diagnostics: *database.Diagnostics,
) !ptz.Variants {
    const query: database.Owned(?tables.owned) = try database.get(
        connection,
        .owned,
        allocator,
        .card_id,
        card_id,
        diagnostics,
    );
    defer query.deinit();

    if (query.value) |owned| return owned.variants.value;

    const default: ptz.Variants = .empty;

    try database.save(
        connection,
        .owned,
        allocator,
        .{
            .card_id = card_id,
            .variants = .from(default),
        },
        diagnostics,
    );

    return default;
}
