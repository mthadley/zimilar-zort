const std = @import("std");
const process = std.process;
const levenshtein = @import("levenshtein.zig");
const ArrayList = std.ArrayList;

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();

    const args = try init.minimal.args.toSlice(allocator);

    if (args.len != 2) {
        std.log.err("Usage: zimilar-sort [NEEDLE]\n", .{});
        process.exit(1);
    }
    const needle = args[1];

    var file_reader = std.Io.File.stdin().reader(init.io, &.{});
    const raw_lines = try file_reader.interface.allocRemaining(allocator, .unlimited);
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
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
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
