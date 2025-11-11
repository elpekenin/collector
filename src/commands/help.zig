const std = @import("std");

const utils = @import("../utils.zig");
const App = @import("../App.zig");

pub fn run(comptime Command: type, app: *App, reader: *std.Io.Reader) !void {
    if (try utils.takeWord(reader)) |_| {
        try app.repl.err(&.{"too many args"}, .{});
        return;
    }

    try app.repl.printInNewLine(&.{
        .{ .text = "available commands:" },
    });

    inline for (@typeInfo(Command).@"enum".fields) |field| {
        // prevent help from listing itself
        if (!std.mem.eql(u8, field.name, "help")) {
            try app.repl.print(&.{
                .{ .text = " " },
                .{ .text = field.name },
            });
        }
    }

    try app.repl.promptInNewLine();
}
