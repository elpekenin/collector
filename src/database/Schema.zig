const jetquery = @import("jetquery");

pub const Owned = jetquery.Model(
    @This(),
    "owned",
    @import("../Owned.zig"),
    .{},
);
