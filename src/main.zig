const std = @import("std");
const process = std.process;
const levenshtein = @import("levenshtein.zig");
const ArrayList = std.ArrayList;

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();

    const args = try process.argsAlloc(allocator);
    defer process.argsFree(allocator, args);

    if (args.len != 2) {
        std.log.err("Usage: zimilar-sort [NEEDLE]\n", .{});
        process.exit(1);
    }
    const needle = args[1];

    const raw_lines = try std.io.getStdIn().readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(raw_lines);

    var lines = ArrayList(Line).init(allocator);
    defer lines.deinit();

    var it = std.mem.tokenize(u8, raw_lines, "\n");

    while (it.next()) |line| {
        const distance = try levenshtein.distance(allocator, needle, line);

        if (distance != 0) {
            try lines.append(.{ .line = line, .distance = distance });
        }
    }

    const lines_slice = lines.toOwnedSlice();
    std.sort.sort(Line, lines_slice, {}, Line.lessThan);

    var writer = std.io.bufferedWriter(std.io.getStdOut().writer());

    for (lines_slice) |line| {
        _ = try writer.write(line.line);
        _ = try writer.write("\n");
    }

    try writer.flush();
}

const Line = struct {
    const Self = @This();

    line: []const u8,
    distance: usize,

    fn lessThan(_: void, left: Self, right: Self) bool {
        return left.distance < right.distance;
    }
};

test {
    std.testing.refAllDecls(@This());
}
