const std = @import("std");

const zqlite = @import("zqlite");
pub const Connection = zqlite.Conn;

const Owned = struct {
    card_id: []const u8,
};

const Options = struct {
    path: [:0]const u8,
    flags: c_int = zqlite.OpenFlags.Create | zqlite.OpenFlags.EXResCode,
};

fn createDb(conn: *zqlite.Conn) !void {
    try conn.exec("CREATE TABLE IF NOT EXISTS owned (card_id text)", .{});
}

pub fn connect(options: Options) !Connection {
    var conn = try zqlite.open(options.path, options.flags);

    try createDb(&conn);

    return conn;
}

pub fn isOwned(conn: *Connection, id: []const u8) !bool {
    const row = try conn.row("SELECT * FROM owned WHERE card_id=?1", .{id}) orelse return false;
    defer row.deinit();

    return true;
}

pub fn addOwned(conn: *Connection, id: []const u8) !void {
    try conn.exec("INSERT INTO owned (card_id) VALUES (?1)", .{id});
}

pub fn rmOwned(conn: *Connection, id: []const u8) !void {
    try conn.exec("DELETE FROM owned WHERE card_id=?1", .{id});
}

pub fn allOwned(allocator: std.mem.Allocator, conn: *Connection) ![]const Owned {
    var rows = try conn.rows("SELECT * FROM owned", .{});
    defer rows.deinit();

    var owned: std.ArrayList(Owned) = .empty;
    defer owned.deinit(allocator);

    while (rows.next()) |row| {
        try owned.append(allocator, .{
            .card_id = row.text(0),
        });
    }

    return owned.toOwnedSlice(allocator);
}
