const std = @import("std");

/// Returns the levenshtein distance between two "strings". This is a Zig
/// implementation of the algorithm from the Rust `strsim` crate:
///
///   https://docs.rs/strsim/0.10.0/src/strsim/lib.rs.html#200-226
///
/// `cache` must have at least `@min(a.len, b.len)` entries. It is owned by
/// the caller so a single buffer can be reused across many calls.
pub fn distance(cache: []usize, a: []const u8, b: []const u8) usize {
    // The cache is indexed by the inner string, so make that the shorter of
    // the two. Levenshtein distance is symmetric, so swapping is free.
    const long, const short = if (a.len >= b.len) .{ a, b } else .{ b, a };

    if (short.len == 0) return long.len;

    for (cache[0..short.len], 0..) |*entry, i| entry.* = i + 1;

    var result: usize = 0;

    for (long, 0..) |charA, i| {
        result = i + 1;
        var distanceB = i;

        for (short, 0..) |charB, j| {
            const cost = @intFromBool(charA != charB);
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
    var cache: [64]usize = undefined;
    try t.expectEqual(@as(usize, 0), distance(&cache, "", ""));
    try t.expectEqual(@as(usize, 0), distance(&cache, "a", "a"));

    try t.expectEqual(@as(usize, 1), distance(&cache, "a", ""));
    try t.expectEqual(@as(usize, 1), distance(&cache, "", "a"));

    try t.expectEqual(@as(usize, 0), distance(&cache, "foo", "foo"));
    try t.expectEqual(@as(usize, 1), distance(&cache, "b", "a"));
    try t.expectEqual(@as(usize, 2), distance(&cache, "gumbo", "gambol"));
    try t.expectEqual(@as(usize, 3), distance(&cache, "mentors", "center"));
    try t.expectEqual(@as(usize, 12), distance(&cache, "hello", "noteventhesame"));
}
