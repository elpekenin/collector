const std = @import("std");

const jetquery = @import("jetquery");

const Owned = @import("Owned.zig");
pub const Schema = @import("database/Schema.zig");

pub const Repo = jetquery.Repo(.postgresql, Schema);

pub const createDb = @import("database/create.zig").createDb;

pub fn getOwned(allocator: std.mem.Allocator, repo: *Repo) ![]Owned {
    const db = try repo.Query(.Owned).all(repo); // this returns some weird type
    defer repo.free(db);

    var owned = try allocator.alloc(Owned, db.len);
    errdefer allocator.free(owned);

    for (db, 0..) |card, i| {
        owned[i] = .{ .card_id = card.card_id };
    }

    return owned;
}
