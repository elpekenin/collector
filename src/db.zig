const std = @import("std");

const zqlite = @import("zqlite");
pub const Connection = zqlite.Conn;

const Owned = @import("Owned.zig");

const Options = struct {
    path: [:0]const u8,
    flags: c_int = zqlite.OpenFlags.Create | zqlite.OpenFlags.EXResCode,
};

// TODO: migrations or something
fn createDb(conn: *zqlite.Conn) !void {
    try conn.exec("CREATE TABLE IF NOT EXISTS owned (card_id text, variant text)", .{});
}

pub fn connect(options: Options) !Connection {
    var conn = try zqlite.open(options.path, options.flags);

    try createDb(&conn);

    return conn;
}

pub fn isOwned(conn: *Connection, id: []const u8, variant: Owned.VariantEnum) !bool {
    const row = try conn.row(
        "SELECT * FROM owned WHERE card_id=?1 AND variant=?2",
        .{ id, @tagName(variant) },
    ) orelse return false;
    defer row.deinit();

    return true;
}

pub fn addOwned(conn: *Connection, id: []const u8, variant: Owned.VariantEnum) !void {
    try conn.exec(
        "INSERT INTO owned (card_id, variant) VALUES (?1, ?2)",
        .{ id, @tagName(variant) },
    );
}

pub fn rmOwned(conn: *Connection, id: []const u8, variant: Owned.VariantEnum) !void {
    try conn.exec(
        "DELETE FROM owned WHERE card_id=?1 AND variant=?2",
        .{ id, @tagName(variant) },
    );
}

pub fn allOwned(allocator: std.mem.Allocator, conn: *Connection) ![]const Owned {
    var rows = try conn.rows("SELECT * FROM owned", .{});
    defer rows.deinit();

    var owned: std.ArrayList(Owned) = .empty;
    defer owned.deinit(allocator);

    while (rows.next()) |row| {
        try owned.append(allocator, .{
            .card_id = row.text(0),
            .variant = std.meta.stringToEnum(
                Owned.VariantEnum,
                row.text(1) orelse unreachable,
            ),
        });
    }

    return owned.toOwnedSlice(allocator);
}

pub fn filename(conn: *Connection) [*c]const u8 {
    return zqlite.c.sqlite3_db_filename(@ptrCast(conn.conn), null);
}
