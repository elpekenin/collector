const std = @import("std");

const ptz = @import("ptz");

pub const VariantEnum = std.meta.FieldEnum(ptz.Variants);

card_id: []const u8,
variant: VariantEnum,
