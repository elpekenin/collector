//! State of the program

const std = @import("std");
const db = @import("db.zig");

allocator: std.mem.Allocator,
conn: db.Connection,
stderr: *std.Io.Writer,
stdout: *std.Io.Writer,
