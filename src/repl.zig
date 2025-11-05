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
const App = @import("App.zig");
const MissingIterator = @import("MissingIterator.zig");
const Repl = @import("repl/Repl.zig");

const Command = enum {
    ls,
    add,
    rm,
};

pub fn run(app: *App) !u8 {
    var buffer: [1024]u8 = undefined;

    var repl: Repl = .create(app.allocator);
    try repl.init(&buffer);

    defer repl.destroy();

    var stop = false;
    while (!stop) {
        const event = try repl.nextEvent() orelse continue;

        switch (event) {
            .exit => |code| return code,
            .input => |line| {
                defer {
                    repl.allocator.free(line);
                    repl.text.reset();
                    repl.showPromptAndInput() catch {
                        stop = true;
                    };
                }

                var reader: std.Io.Reader = .fixed(line);

                // on empty line, do nothing
                const str = try utils.takeWord(&reader) orelse {
                    try repl.advanceLine();
                    try repl.render();
                    continue;
                };

                const command = std.meta.stringToEnum(Command, str) orelse {
                    try repl.err(&.{ "unknown command: ", str });
                    try repl.render();
                    continue;
                };

                switch (command) {
                    .ls => {
                        const name = try utils.takeWord(&reader) orelse {
                            try repl.err(&.{"missing Pokemon's name"});
                            try repl.render();
                            continue;
                        };

                        var missing: MissingIterator = try .create(app.allocator, &app.conn, .{
                            .where = &.{
                                .like(.name, name),
                            },
                        });
                        defer missing.destroy();

                        // used for image links, so that text lives enough to be rendered
                        var arena: std.heap.ArenaAllocator = .init(app.allocator);
                        defer arena.deinit();

                        var offset: u16 = 1;
                        while (try missing.next()) |card| : (offset += 1) {
                            // allow to break loop with Ctrl+C
                            if (repl.loop.tryEvent()) |evt| {
                                switch (evt) {
                                    // NOTE: this will drop some input, but we can live with it
                                    .key_press => |key| {
                                        if (key.mods.ctrl and key.codepoint == 'c') {
                                            try repl.printInNewLine(&.{"interrupted"}, .{});
                                            break;
                                        }
                                    },
                                    // re-publish event for later consumption
                                    else => repl.loop.postEvent(evt),
                                }
                            }

                            const pokemon = try utils.unwrapPokemon(card);

                            try repl.advanceLine();
                            try repl.print(&.{ "[", pokemon.id, "] ", pokemon.name, " " }, .{});

                            if (pokemon.image) |image| {
                                var allocating: std.Io.Writer.Allocating = .init(arena.allocator());
                                const writer = &allocating.writer;

                                try image.toUrl(writer, .high, .jpg);

                                try repl.printLink(&.{"(image)"}, .{ .uri = try allocating.toOwnedSlice() });
                            }

                            // render on each card, for TUI feedback
                            try repl.render();
                        }

                        try repl.advanceLine();
                        try repl.render();
                    },
                    .add => {
                        const id = try utils.takeWord(&reader) orelse {
                            try repl.err(&.{"missing card's id"});
                            try repl.render();
                            continue;
                        };

                        if (try db.isOwned(&app.conn, id)) {
                            try repl.warn(&.{"already owned"});
                            try repl.render();
                            continue;
                        }

                        utils.validateCardId(app.allocator, id) catch |e| {
                            switch (e) {
                                error.NotACard => try repl.warn(&.{"not a card"}),
                                error.NonPokemonCard => try repl.warn(&.{"card is not a pokemon"}),
                                error.UnexpectedError => {
                                    try repl.err(&.{"unexpected error"});
                                    try repl.render();
                                    return 1;
                                },
                            }

                            try repl.render();
                            continue;
                        };

                        try db.addOwned(&app.conn, id);

                        try repl.printInNewLine(&.{"added"}, .{});
                        try repl.render();
                    },
                    .rm => {
                        const id = try utils.takeWord(&reader) orelse {
                            try repl.err(&.{"missing card's id"});
                            try repl.render();
                            continue;
                        };

                        if (!try db.isOwned(&app.conn, id)) {
                            try repl.warn(&.{"not in database"});
                            try repl.render();
                            continue;
                        }

                        utils.validateCardId(app.allocator, id) catch |e| {
                            switch (e) {
                                error.NotACard => try repl.warn(&.{"not a card"}),
                                error.NonPokemonCard => try repl.warn(&.{"card is not a pokemon"}),
                                error.UnexpectedError => {
                                    try repl.err(&.{"unexpected error"});
                                    try repl.render();
                                    return 1;
                                },
                            }

                            try repl.render();
                            continue;
                        };

                        try db.rmOwned(&app.conn, id);

                        try repl.printInNewLine(&.{"removed"}, .{});
                        try repl.render();
                    },
                }
            },
        }
    }

    return 1;
}
