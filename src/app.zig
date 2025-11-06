//! Interact with the database in a REPL

// TODO:
//   - parse user input
//   - act accordingly
//   - show image instead of link when kitty supported

const std = @import("std");

const vaxis = @import("vaxis");
const Input = vaxis.widgets.TextInput;

const db = @import("db.zig");
const utils = @import("utils.zig");
const Ctx = @import("Ctx.zig");
const MissingIterator = @import("MissingIterator.zig");
const Repl = @import("repl/Repl.zig");

const Command = enum {
    @"?",
    add,
    clear,
    db,
    exit,
    ls,
    rm,
};

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
        const str = try utils.takeWord(reader) orelse {
            try repl.newPrompt();
            continue;
        };

        const command = std.meta.stringToEnum(Command, str) orelse {
            try repl.err(&.{ "unknown command: ", str });
            continue;
        };

        switch (command) {
            .exit => {
                if (try utils.takeWord(reader)) |_| {
                    try repl.err(&.{"too many args"});
                    continue;
                }

                return 0;
            },

            .clear => {
                if (try utils.takeWord(reader)) |_| {
                    try repl.err(&.{"too many args"});
                    continue;
                }
                try repl.clear();
            },

            .@"?" => {
                if (try utils.takeWord(reader)) |_| {
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
                if (try utils.takeWord(reader)) |_| {
                    try repl.err(&.{"too many args"});
                    continue;
                }

                try repl.printInNewLine(&.{
                    .{ .text = "database stored at: " },
                    .{ .text = std.mem.sliceTo(db.filename(&ctx.conn), 0) },
                });

                try repl.newPrompt();
            },

            .ls => {
                const name = try utils.takeWord(reader) orelse {
                    try repl.err(&.{"missing Pokemon's name"});
                    continue;
                };

                if (try utils.takeWord(reader)) |_| {
                    try repl.err(&.{"too many args"});
                    continue;
                }

                var missing: MissingIterator = try .create(ctx.allocator, &ctx.conn, .{
                    .where = &.{
                        .like(.name, name),
                    },
                });
                defer missing.destroy();

                // used for image links, so that text lives enough to be rendered
                var arena: std.heap.ArenaAllocator = .init(ctx.allocator);
                defer arena.deinit();

                var offset: u16 = 1;
                while (try missing.next()) |card| : (offset += 1) {
                    // allow to break loop with Ctrl+C
                    if (repl.loop.tryEvent()) |evt| {
                        switch (evt) {
                            // NOTE: this will drop some input, but we can live with it
                            .key_press => |key| {
                                if (key.mods.ctrl and key.codepoint == 'c') {
                                    try repl.printInNewLine(&.{
                                        .{ .text = "interrupted" },
                                    });

                                    break;
                                }
                            },
                            // re-publish event for later consumption
                            else => repl.loop.postEvent(evt),
                        }
                    }

                    const pokemon = try utils.unwrapPokemon(card);

                    try repl.addLine();
                    try repl.print(&.{
                        .{ .text = "[" },
                        .{ .text = pokemon.id },
                        .{ .text = "] " },
                        .{ .text = pokemon.name },
                        .{ .text = " " },
                    });

                    if (pokemon.image) |image| {
                        var allocating: std.Io.Writer.Allocating = .init(arena.allocator());
                        const writer = &allocating.writer;

                        try image.toUrl(writer, .high, .jpg);

                        try repl.print(&.{
                            .{ .text = "(image)", .link = .{ .uri = try allocating.toOwnedSlice() } },
                        });
                    }

                    // render on each card, so that screen is not frozen
                    try repl.render();
                }

                try repl.newPrompt();
            },

            .add,
            .rm,
            => |cmd| {
                const adding = cmd == .add;

                const id = try utils.takeWord(reader) orelse {
                    try repl.err(&.{"missing card's id"});
                    continue;
                };

                if (try utils.takeWord(reader)) |_| {
                    try repl.err(&.{"too many args"});
                    continue;
                }

                const owned = try db.isOwned(&ctx.conn, id);
                if (owned == adding) {
                    const msg = if (adding) "already in database" else "not in database";
                    try repl.warn(&.{msg});
                    continue;
                }

                utils.validateCardId(ctx.allocator, id) catch |e| {
                    switch (e) {
                        error.NotACard => try repl.warn(&.{"not a card"}),
                        error.NonPokemonCard => try repl.warn(&.{"card is not a pokemon"}),
                        error.UnexpectedError => try repl.err(&.{"unexpected error"}),
                    }

                    continue;
                };

                if (adding) {
                    try db.addOwned(&ctx.conn, id);
                } else {
                    try db.rmOwned(&ctx.conn, id);
                }

                const msg = if (adding) "added" else "removed";
                try repl.success(&.{msg});
            },
        }
    }
}
