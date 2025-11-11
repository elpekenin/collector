const std = @import("std");

const utils = @import("../utils.zig");
const App = @import("../App.zig");

pub fn run(app: *App, reader: *std.Io.Reader) !void {
    if (try utils.takeWord(reader)) |_| {
        try app.repl.err(&.{"too many args"}, .{});
        return;
    }

    app.exit(0);
}
