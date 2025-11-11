const std = @import("std");

const database = @import("../database.zig");
const utils = @import("../utils.zig");
const App = @import("../App.zig");

pub fn run(app: *App, reader: *std.Io.Reader) !void {
    if (try utils.takeWord(reader)) |_| {
        try app.repl.err(&.{"too many args"}, .{});
        return;
    }

    try app.repl.printInNewLine(&.{
        .{ .text = "database stored at: " },
        .{ .text = std.mem.sliceTo(database.getFilename(&app.connection), 0) },
    });

    try app.repl.promptInNewLine();
}
