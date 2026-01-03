const std = @import("std");
const process = std.process;
const levenshtein = @import("levenshtein.zig");
const ArrayList = std.ArrayList;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();

    const args = try process.argsAlloc(allocator);
    defer process.argsFree(allocator, args);

    if (args.len != 2) {
        std.log.err("Usage: zimilar-sort [NEEDLE]\n", .{});
        process.exit(1);
    }
    const needle = args[1];

    const raw_lines = try std.fs.File.stdin().readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(raw_lines);

    var lines = ArrayList(Line).empty;
    defer lines.deinit(allocator);

    var it = std.mem.tokenizeAny(u8, raw_lines, "\n");

    while (it.next()) |chars| {
        const distance = try levenshtein.distance(allocator, needle, chars);

        if (distance != 0) {
            try lines.append(allocator, .{ .chars = chars, .distance = distance });
        }
    }

    std.sort.pdq(Line, lines.items, {}, Line.lessThan);

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    for (lines.items) |line| stdout.print("{s}\n", .{line.chars}) catch |err| {
        std.log.err("Error writing to stdout: {}\n", .{err});
        process.exit(1);
    };

    try stdout.flush();
}

const Line = struct {
    const Self = @This();

    chars: []const u8,
    distance: usize,

    fn lessThan(_: void, left: Self, right: Self) bool {
        return left.distance < right.distance;
    }
};

test {
    std.testing.refAllDecls(@This());
}
