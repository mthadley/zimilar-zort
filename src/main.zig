const std = @import("std");
const levenshtein = @import("levenshtein.zig");

pub fn main() anyerror!void {
    std.log.info("All your codebase are belong to us.", .{});
}

test {
    std.testing.refAllDecls(@This());
}
