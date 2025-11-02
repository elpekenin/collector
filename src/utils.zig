const std = @import("std");
const sdk = @import("ptz").Sdk(.en);

pub fn printPrice(writer: *std.Io.Writer, card: sdk.Card.Pokemon) !void {
    const cardmarket = if (card.pricing) |pricing|
        if (pricing.cardmarket) |cardmarket|
            cardmarket
        else
            return
    else
        return;

    if (cardmarket.trend) |trend| {
        try writer.print("{d}", .{trend});
    } else {
        try writer.print("???", .{});
    }

    try writer.print("{s}", .{cardmarket.unit orelse ""});
}
