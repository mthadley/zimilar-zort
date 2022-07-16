const std = @import("std");
const Allocator = std.mem.Allocator;
const Matrix = @import("matrix.zig");

pub fn distance(allocator: Allocator, a: []const u8, b: []const u8) !usize {
    if (a.len == 0 and b.len == 0) return 0;
    if (a.len == 0) return b.len;
    if (b.len == 0) return a.len;

    const height = b.len + 1;
    const width = a.len + 1;

    var matrix = try Matrix.init(allocator, height, width);
    defer matrix.deinit();

    // Initialize bounds of matrix:
    //     f o o
    //   0 1 2 3
    // b 1 x x x
    // a 2 x x x
    // r 3 x x x
    {
        var i: usize = 0;
        while (i < width) : (i += 1) matrix.set(0, i, i);
    }
    {
        var i: usize = 0;
        while (i < height) : (i += 1) matrix.set(i, 0, i);
    }

    {
        var i: usize = 1;
        while (i < height) : (i += 1) {
            var j: usize = 1;
            while (j < width) : (j += 1) {
                const cost: u1 = if (b[i - 1] == a[j - 1]) 0 else 1;

                const above = matrix.get(i - 1, j) + 1;
                const left = matrix.get(i, j - 1) + 1;
                const diag = matrix.get(i - 1, j - 1) + cost;

                matrix.set(i, j, @minimum(above, @minimum(left, diag)));
            }
        }
    }

    return matrix.get(height - 1, width - 1);
}

const t = std.testing;

test {
    std.testing.refAllDecls(@This());
}

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
