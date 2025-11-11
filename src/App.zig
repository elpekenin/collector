//! State of the program

const std = @import("std");

const database = @import("database.zig");
const Repl = @import("Repl.zig");

const App = @This();

allocator: std.mem.Allocator,
connection: database.Connection,
repl: Repl,
stderr: *std.Io.Writer,
stdout: *std.Io.Writer,
stop: bool,
exitcode: u8,

pub fn exit(self: *App, code: u8) void {
    self.stop = true;
    self.exitcode = code;
}
