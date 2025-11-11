//! Tiny wrapper on top of sqlite.Database
//!
//! Used to store a writer (stderr) where to report errors when preparing queries and whatnot
//! This prevents having to pass it as an argument on every function call

const std = @import("std");
const compPrint = std.fmt.comptimePrint;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

const sqlite = @import("sqlite");
const zmig = @import("zmig");

const ptz = @import("ptz");

pub const Connection = sqlite.Db;
pub const Diagnostics = sqlite.Diagnostics;

pub const types = struct {
    pub const Variants = struct {
        /// how the type is stored in database
        pub const BaseType = []const u8;

        value: ptz.Variants,

        pub const empty: Variants = .from(.empty);

        pub fn from(value: ptz.Variants) Variants {
            return .{ .value = value };
        }

        pub fn bindField(self: Variants, allocator: Allocator) !BaseType {
            var allocating: std.Io.Writer.Allocating = .init(allocator);
            defer allocating.deinit();

            var formatter: std.json.Formatter(ptz.Variants) = .{
                .value = self.value,
                .options = .{},
            };
            try formatter.format(&allocating.writer);

            return allocating.toOwnedSlice();
        }

        pub fn readField(allocator: Allocator, base: BaseType) !Variants {
            const parsed: std.json.Parsed(ptz.Variants) = try std.json.parseFromSlice(ptz.Variants, allocator, base, .{
                .allocate = .alloc_if_needed,
            });

            return .from(parsed.value);
        }
    };
};

pub const tables = struct {
    pub const pokemon = struct {
        card_id: []const u8,
        name: []const u8,
        image_url: []const u8,
        variants: types.Variants,
    };

    pub const owned = struct {
        card_id: []const u8,
        variants: types.Variants,
    };
};

fn TableType(comptime table: Table) type {
    return @field(tables, @tagName(table));
}

const Table = std.meta.DeclEnum(tables);

pub fn init(allocator: Allocator, path: [:0]const u8, diagnostics: *zmig.Diagnostics) !Connection {
    var database: Connection = try .init(.{
        .mode = .{ .File = path },
        .open_flags = .{
            .create = true,
            .write = true,
        },
    });

    try zmig.applyMigrations(&database, allocator, .{ .diagnostics = diagnostics });

    return database;
}

pub fn get(
    connection: *Connection,
    comptime table: Table,
    allocator: Allocator,
    comptime column: std.meta.FieldEnum(TableType(table)),
    value: @FieldType(TableType(table), @tagName(column)),
    diagnostics: *sqlite.Diagnostics,
) !Owned(?TableType(table)) {
    const query = comptime compPrint("SELECT * FROM {s} WHERE {s}=?", .{
        @tagName(table),
        @tagName(column),
    });

    var stmt = try connection.prepareWithDiags(query, .{
        .diags = diagnostics,
    });
    defer stmt.deinit();

    const arena = try newArena(allocator);
    errdefer allocator.destroy(arena);

    return .{
        .arena = arena,
        .value = try stmt.oneAlloc(
            TableType(table),
            arena.allocator(),
            .{},
            .{value},
        ),
    };
}

pub fn all(
    connection: *Connection,
    comptime table: Table,
    allocator: Allocator,
    diagnostics: *sqlite.Diagnostics,
) !Owned([]const TableType(table)) {
    const query = comptime compPrint("SELECT * FROM {s}", .{@tagName(table)});

    var stmt = try connection.prepareWithDiags(query, .{ .diags = diagnostics });
    defer stmt.deinit();

    const arena = try newArena(allocator);
    errdefer allocator.destroy(arena);

    return .{
        .arena = arena,
        .value = try stmt.all(
            TableType(table),
            arena.allocator(),
            .{},
            .{},
        ),
    };
}

/// inserts or updates the given values
pub fn save(
    connection: *Connection,
    comptime table: Table,
    allocator: Allocator,
    value: TableType(table),
    diagnostics: *sqlite.Diagnostics,
) !void {
    const query = comptime queryBuilder(
        table,
        queryBuilder(
            table,
            compPrint("REPLACE INTO {s} (", .{@tagName(table)}),
            nameCommaSpace,
            nameCloseParen,
        ) ++ " VALUES (",
        placeholderCommaSpace,
        placeholderCloseParen,
    );

    var stmt = try connection.prepareWithDiags(query, .{ .diags = diagnostics,});
    defer stmt.deinit();

    // HACK: work around sqlite's leak
    const arena = try newArena(allocator);
    allocator.destroy(arena);
    defer arena.deinit();

    try stmt.execAlloc(arena.allocator(), .{}, value);
}

pub fn getFilename(connection: *Connection) [*c]const u8 {
    return sqlite.c.sqlite3_db_filename(connection.db, null);
}

// internal query-related code

const StructField = std.builtin.Type.StructField;
const Format = fn (comptime []const u8, StructField) []const u8;

fn queryBuilder(
    comptime table: Table,
    query: []const u8,
    formatEach: Format,
    formatLast: Format,
) []const u8 {
    if (!@inComptime()) @compileError("must call this in comptime");

    var q = query;

    const fields = @typeInfo(TableType(table)).@"struct".fields;

    if (fields.len == 0) unreachable;
    if (fields.len > 1) {
        inline for (fields[0 .. fields.len - 1]) |field| {
            q = formatEach(q, field);
        }
    }

    return formatLast(q, fields[fields.len - 1]);
}

fn spaceNamePlaceholder(comptime query: []const u8, field: StructField) []const u8 {
    return query ++ compPrint(" {s}=?", .{field.name});
}

fn spaceNamePlaceholderAnd(comptime query: []const u8, field: StructField) []const u8 {
    return query ++ compPrint(" {s}=? AND", .{field.name});
}

fn spaceNamePlaceholderCloseParen(comptime query: []const u8, field: StructField) []const u8 {
    return query ++ compPrint(" {s}=?)", .{field.name});
}

fn nameCommaSpace(comptime query: []const u8, field: StructField) []const u8 {
    return query ++ compPrint("{s}, ", .{field.name});
}

fn nameCloseParen(comptime query: []const u8, field: StructField) []const u8 {
    return query ++ compPrint("{s})", .{field.name});
}

fn placeholderCommaSpace(comptime query: []const u8, _: StructField) []const u8 {
    return query ++ "?, ";
}

fn placeholderCloseParen(comptime query: []const u8, _: StructField) []const u8 {
    return query ++ "?)";
}

fn newArena(allocator: Allocator) Allocator.Error!*ArenaAllocator {
    const arena = try allocator.create(ArenaAllocator);
    arena.* = .init(allocator);
    return arena;
}

/// Caller-owned value, with a method to free it
pub fn Owned(comptime T: type) type {
    return struct {
        value: T,
        arena: *ArenaAllocator,

        pub fn deinit(self: @This()) void {
            const child = self.arena.child_allocator;
            self.arena.deinit();
            child.destroy(self.arena);
        }
    };
}
