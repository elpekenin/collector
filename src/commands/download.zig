const std = @import("std");

const sdk = @import("ptz").Sdk(.en);

const database = @import("../database.zig");
const utils = @import("../utils.zig");
const App = @import("../App.zig");

const spinner: []const []const u8 = &.{
    "⠋",
    "⠙",
    "⠹",
    "⠸",
    "⠼",
    "⠴",
    "⠦",
    "⠧",
    "⠇",
    "⠏",
};

fn cardCount(allocator: std.mem.Allocator, params: sdk.Iterator(sdk.Card.Brief).Params) !usize {
    // prevent using null as page size (API using a default value)
    // force a big number not to need a lot of queries
    var fixed_params = params;
    fixed_params.page_size = 100_000;

    var iterator = sdk.Card.all(allocator, fixed_params);

    var count: usize = 0;
    while (try iterator.next()) |page| {
        count += page.len;
    }

    return count;
}

pub fn run(app: *App, reader: *std.Io.Reader) !void {
    const name = try utils.takeWord(reader) orelse "";

    if (try utils.takeWord(reader)) |_| {
        try app.repl.err(&.{"too many args"}, .{});
        return;
    }

    try app.repl.warn(&.{"note: this may take a while"}, .{ .prompt = false });
    app.repl.rmLine();
    try app.repl.render();

    var iterator = sdk.Card.Brief.iterator(app.allocator, .{
        .where = &.{
            .like(.name, name),
        },
    });

    const card_count = try cardCount(app.allocator, iterator.q.params);

    var messages: std.ArrayList([]const u8) = .empty;
    defer {
        for (messages.items) |message| {
            app.allocator.free(message);
        }
        messages.deinit(app.allocator);
    }

    var allocating: std.Io.Writer.Allocating = .init(app.allocator);
    defer allocating.deinit();

    const tcgp: sdk.Serie = try .get(app.allocator, .{
        .id = "tcgp",
    });
    defer tcgp.deinit();

    var interrupted, var downloaded: usize = .{ false, 0 };
    briefs_loop: while (try iterator.next()) |briefs| {
        defer briefs[briefs.len - 1].deinit();

        for (briefs) |brief| {
            if (try utils.interruptRequested(&app.repl)) {
                interrupted = true;
                break :briefs_loop;
            }

            allocating.clearRetainingCapacity();

            // do not stale the TUI
            try app.repl.render();

            if (utils.isFromSerie(brief.id, tcgp)) continue;

            const card: sdk.Card = try .get(app.allocator, .{
                .id = brief.id,
            });
            defer card.deinit();

            const pokemon = switch (card) {
                .pokemon => |pokemon| pokemon,
                else => continue, // ignore trainer/energy cards
            };

            if (pokemon.variants.isEmpty()) {
                allocating.clearRetainingCapacity();
                try allocating.writer.print("'{s}' has no defined variants, ignored it", .{pokemon.id});

                const message = try allocating.toOwnedSlice();
                errdefer app.allocator.free(message);

                try messages.append(app.allocator, message);

                continue;
            }

            downloaded += 1;

            if (pokemon.image) |image| {
                allocating.clearRetainingCapacity();
                try image.format(&allocating.writer);
            }

            const url = try allocating.toOwnedSlice();
            defer app.allocator.free(url);

            var diagnostics: database.Diagnostics = undefined;
            database.save(
                &app.connection,
                .pokemon,
                app.allocator,
                .{
                    .card_id = pokemon.id,
                    .name = pokemon.name,
                    .image_url = url,
                    .variants = .from(pokemon.variants),
                },
                &diagnostics,
            ) catch |e| {
                try app.stderr.print("{f}\n", .{diagnostics});
                return e;
            };

            // remove the 2 lines introduced by previous iteration
            if (downloaded > 1) {
                app.repl.rmLine(); // last: <name>
                app.repl.rmLine(); // <spinner> Downloaded <count>
            }

            allocating.clearRetainingCapacity();
            try allocating.writer.print("{s} {d}/{d}", .{
                spinner[downloaded % spinner.len],
                downloaded,
                card_count,
            });

            const progress = try allocating.toOwnedSlice();
            defer app.allocator.free(progress);

            try app.repl.printInNewLine(&.{
                .{ .text = progress },
            });

            try app.repl.printInNewLine(&.{
                .{ .text = pokemon.name },
                .{ .text = " (" },
                .{ .text = pokemon.id },
                .{ .text = ")" },
            });
        }
    }

    for (messages.items) |message| {
        try app.repl.err(&.{message}, .{ .prompt = false });
        app.repl.rmLine();
    }

    if (!interrupted and downloaded == 0) {
        try app.repl.err(&.{ "there are no Pokemon cards with '", name, "' in their name" }, .{});
        return;
    }

    try app.repl.promptInNewLine();
}
