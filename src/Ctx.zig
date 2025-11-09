//! State of the program

const std = @import("std");
const Database = @import("Database.zig");

allocator: std.mem.Allocator,
database: *Database,
stderr: *std.Io.Writer,
stdout: *std.Io.Writer,
