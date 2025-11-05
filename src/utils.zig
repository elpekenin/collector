const std = @import("std");

const sdk = @import("ptz").Sdk(.en);

const UnwrapError = error{
    NonPokemonCard,
};

const ValidationError = UnwrapError || error {
    NotACard,
    UnexpectedError,
};

/// returns whether something was printed
pub fn printPrice(writer: *std.Io.Writer, pricing: sdk.Pricing) !bool {
    const cardmarket = if (pricing.cardmarket) |cardmarket|
        cardmarket
    else
        return false;

    if (cardmarket.trend) |trend| {
        try writer.print("{d}", .{trend});
    } else {
        try writer.print("???", .{});
    }

    try writer.print("{s}", .{cardmarket.unit orelse ""});

    return true;
}

/// get the Pokemon payload from a Card, or throw an error
pub fn unwrapPokemon(card: sdk.Card) UnwrapError!sdk.Card.Pokemon {
    return switch (card) {
        .pokemon => |pokemon| pokemon,
        else => error.NonPokemonCard,
    };
}

/// check if the given text is indeed a card's id, and it is a Pokemon
pub fn validateCardId(allocator: std.mem.Allocator, id: []const u8) ValidationError!void {
    const card = sdk.Card.get(allocator, .{
        .id = id,
    }) catch |e| switch (e) {
        error.ServerErrorStatus => return error.NotACard,
        else => return error.UnexpectedError,
    };
    defer card.free(allocator);

    _ = try unwrapPokemon(card);
}

/// take the next word from a reader
pub fn takeWord(reader: *std.Io.Reader) !?[]const u8 {
    while (true) {
        const word = try reader.takeDelimiter(' ') orelse return null;

        if (word.len > 0) {
            return word;
        }
    }
}
