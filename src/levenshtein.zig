const std = @import("std");

pub fn distance(allocator: std.mem.Allocator, a: []const u8, b: []const u8) !usize {
    const matrix = try allocator.alloc([]usize, b.len + 1);
    defer allocator.free(matrix);
    defer {
        for (matrix) |row| {
            allocator.free(row);
        }
    }

    for (matrix) |*row, i| {
        row.* = try allocator.alloc(usize, a.len + 1);

        if (i == 0) {
            for (row.*) |*col, j| {
                col.* = j;
            }
        } else {
            row.*[0] = i;
        }
    }

    for (matrix) |*row, i| {
        if (i == 0) continue;

        for (row.*) |*col, j| {
            if (j == 0) continue;

            const cost: usize = if (b[i - 1] == a[j - 1]) 0 else 1;

            const above = matrix[i - 1][j] + 1;
            const left = matrix[i][j - 1] + 1;
            const diag = matrix[i - 1][j - 1] + cost;

            col.* = @minimum(above, @minimum(left, diag));
        }
    }

    return matrix[b.len - 1][a.len - 1];
}

const t = std.testing;

test "levenshtein_distnace" {
    try t.expectEqual(@as(usize, 2), try distance(t.allocator, "gumbo", "gambol"));
    try t.expectEqual(@as(usize, 3), try distance(t.allocator, "mentors", "center"));
}
