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

    const raw_lines = try std.io.getStdIn().readToEndAlloc(allocator, MAX_STDIN_SIZE);

    var lines = ArrayList(Line).init(allocator);
    var it = std.mem.tokenize(u8, raw_lines, "\n");

    while (it.next()) |line| {
        try lines.append(.{
            .line = line,
            .distance = try levenshtein.distance(allocator, needle, line),
        });
    }

    const lines_slice = lines.toOwnedSlice();

    std.sort.sort(Line, lines_slice, Line.SortContext{}, Line.lessThan);

    const stdout = std.io.getStdOut().writer();
    for (lines_slice) |line| {
        try stdout.print("{s}\n", .{line.line});
    }
}

const MAX_STDIN_SIZE = 5_000_000_000_000;

const Line = struct {
    const Self = @This();

    line: []const u8,
    distance: usize,

    const SortContext = struct {};

    fn lessThan(_: SortContext, left: Line, right: Line) bool {
        return left.distance < right.distance;
    }
};

test {
    std.testing.refAllDecls(@This());
}
