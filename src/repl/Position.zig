const vaxis = @import("vaxis");

const Position = @This();

col: u16,
row: u16,

pub const zero: Position = .{
    .col = 0,
    .row = 0,
};

pub fn reset(self: *Position) void {
    self = .zero;
}

pub fn advanceLine(self: *Position) void {
    self.col = 0;
    self.row += 1;
}

pub fn update(self: *Position, res: vaxis.Window.PrintResult) void {
    self.col = res.col;
    self.row = res.row;
}

pub fn toOptions(self: *Position) vaxis.Window.PrintOptions {
    return .{
        .col_offset = self.col,
        .row_offset = self.row,
    };
}
