const std = @import("std");

const jetquery = @import("jetquery");

const Owned = @import("Owned.zig");
pub const Schema = @import("database/Schema.zig");

pub const Repo = jetquery.Repo(.postgresql, Schema);
pub const Query = Repo._Query;

pub const createDb = @import("database/create.zig").createDb;

// TODO: opt-in logging?
/// prevent logging of every query
/// but do keep error reporting
fn eventCallback(event: jetquery.events.Event) !void {
    if (event.err) |_| {
        return jetquery.events.defaultCallback(event);
    }
}

pub fn initRepo(allocator: std.mem.Allocator) !Repo {
    return .init(allocator, .{
        // default initializer:
        //   - reads user and password from env (JETQUERY_*)
        //   - uses default port (5432)
        //   - sets other params to default values
        .adapter = .{
            .database = "collector",
        },
        .eventCallback = eventCallback,
    });
}

pub fn getOwned(allocator: std.mem.Allocator, repo: *Repo) ![]Owned {
    const db = try Query(.Owned).all(repo); // this returns some weird type
    defer repo.free(db);

    var owned = try allocator.alloc(Owned, db.len);
    errdefer allocator.free(owned);

    for (db, 0..) |card, i| {
        owned[i] = .{ .card_id = card.card_id };
    }

    return owned;
}
