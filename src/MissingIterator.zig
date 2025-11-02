//! Iterate over NOT owned cards

const std = @import("std");

const database = @import("database.zig");
const Owned = @import("Owned.zig");

const sdk = @import("ptz").Sdk(.en);

const MissingIterator = @This();

const Data = struct {
    owned: []const Owned,
    tcgp: sdk.Serie,
};

const State = struct {
    iterator: sdk.Iterator(sdk.Card.Brief),
    briefs: ?[]const sdk.Card.Brief,
};

allocator: std.mem.Allocator,
repo: *database.Repo,
data: Data,
state: State,

pub fn create(allocator: std.mem.Allocator, repo: *database.Repo, name: []const u8) !MissingIterator {
    const owned = try database.getOwned(allocator, repo);

    var iterator: sdk.Iterator(sdk.Card.Brief) = .new(.{
        .where = &.{
            .like(.name, name),
        },
    });

    const briefs = try iterator.next(allocator) orelse {
        return error.NoCardsFound;
    };

    return .{
        .allocator = allocator,
        .repo = repo,
        .data = .{
            .owned = owned,
            .tcgp = try .get(allocator, .{ .id = "tcgp" }),
        },
        .state = .{
            .iterator = iterator,
            .briefs = briefs,
        },
    };
}

fn advanceBriefs(self: *MissingIterator, i: usize) !void {
    if (self.state.briefs) |briefs| {
        if (briefs.len > i) {
            self.state.briefs = briefs[i + 1 ..];
            return;
        }
    }

    self.state.briefs = try self.state.iterator.next(self.allocator);
}

fn isFromSerie(brief: sdk.Card.Brief, tcgp: sdk.Serie) bool {
    for (tcgp.sets) |set| {
        if (std.mem.startsWith(u8, brief.id, set.id)) {
            return true;
        }
    }

    return false;
}

fn isOwned(self: *const MissingIterator, card_id: []const u8) bool {
    for (self.data.owned) |item| {
        if (std.mem.eql(u8, card_id, item.card_id)) {
            return true;
        }
    }

    return false;
}

pub fn next(self: *MissingIterator) !?sdk.Card {
    const briefs = self.state.briefs orelse return null;

    for (briefs, 0..) |brief, i| {
        if (isFromSerie(brief, self.data.tcgp)) continue;
        if (self.isOwned(brief.id)) continue;

        try self.advanceBriefs(i);

        return try .get(self.allocator, .{
            .id = brief.id,
        });
    }

    // nothing matched, try again by resetting briefs
    try self.advanceBriefs(briefs.len + 1);

    return self.next();
}

pub fn destroy(self: *MissingIterator) void {
    self.allocator.free(self.data.owned);
}
