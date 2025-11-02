const std = @import("std");

const jetquery = @import("jetquery");
const Column = jetquery.schema.Column;
const t = jetquery.schema.table;

const database = @import("../database.zig");
const Repo = database.Repo;
const Schema = database.Schema;

fn toColumn(comptime field: std.builtin.Type.StructField) Column {
    const T = field.type;
    const name = field.name;

    switch (T) {
        []const u8 => {
            return t.column(name, .string, .{});
        },
        else => {},
    }

    const info = @typeInfo(T);
    switch (info) {
        .optional => |op| {
            var non_optional = field;
            non_optional.type = op.child;

            var column = toColumn(non_optional);
            column.options.optional = true;

            return column;
        },
        else => {},
    }

    const msg = std.fmt.comptimePrint("unsupported type: {}", .{T});
    @compileError(msg);
}

fn getColumns(comptime Table: type) []const Column {
    var columns: []const Column = &.{};

    inline for (@typeInfo(Table.Definition).@"struct".fields) |field| {
        if (!std.mem.eql(u8, "id", field.name)) {
            columns = columns ++ &[_]Column{
                toColumn(field),
            };
        }
    }

    return columns;
}

pub fn createDb(repo: *Repo) !void {
    inline for (@typeInfo(Schema).@"struct".decls) |table| {
        const Table = @field(Schema, table.name);
        try repo.createTable(Table.name, getColumns(Table), .{ .if_not_exists = true });
    }
}
