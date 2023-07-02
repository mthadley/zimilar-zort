const std = @import("std");
const Allocator = std.mem.Allocator;

/// Returns the levenshtein distance between two "strings". This is a Zig
/// implementation of the algorithm from the Rust `strsim` crate:
///
///   https://docs.rs/strsim/0.10.0/src/strsim/lib.rs.html#200-226
///
pub fn distance(allocator: Allocator, a: []const u8, b: []const u8) !usize {
    if (a.len == 0) return b.len;

    var cache = try allocator.alloc(usize, b.len);
    defer allocator.free(cache);

    for (cache) |*entry, i| entry.* = i + 1;

    var result: usize = 0;

    for (a) |charA, i| {
        result = i + 1;
        var distanceB = i;

        for (b) |charB, j| {
            const cost: u1 = if (charA == charB) 0 else 1;
            const distanceA = distanceB + cost;

            distanceB = cache[j];
            result = @min(result + 1, @min(distanceA, distanceB + 1));
            cache[j] = result;
        }
    }

    return result;
}

const t = std.testing;

test "distance" {
    try t.expectEqual(@as(usize, 0), try distance(t.allocator, "", ""));
    try t.expectEqual(@as(usize, 0), try distance(t.allocator, "a", "a"));

    try t.expectEqual(@as(usize, 1), try distance(t.allocator, "a", ""));
    try t.expectEqual(@as(usize, 1), try distance(t.allocator, "", "a"));

    try t.expectEqual(@as(usize, 0), try distance(t.allocator, "foo", "foo"));
    try t.expectEqual(@as(usize, 1), try distance(t.allocator, "b", "a"));
    try t.expectEqual(@as(usize, 2), try distance(t.allocator, "gumbo", "gambol"));
    try t.expectEqual(@as(usize, 3), try distance(t.allocator, "mentors", "center"));
    try t.expectEqual(@as(usize, 12), try distance(t.allocator, "hello", "noteventhesame"));
}
