const std = @import("std");
const process = std.process;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const levenshtein = @import("levenshtein.zig");
const myers = @import("myers.zig");

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

    // There is one line per newline, plus a possible unterminated final line.
    var sorter = try Sorter.init(allocator, needle, std.mem.count(u8, raw_lines, "\n") + 1);
    defer sorter.deinit();

    var it = std.mem.tokenizeAny(u8, raw_lines, "\n");
    while (it.next()) |line| try sorter.add(line);

    // A larger buffer keeps the per-line writes from turning into one syscall
    // each.
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    for (sorter.sort()) |line| stdout.print("{s}\n", .{line.chars}) catch |err| switch (err) {
        error.WriteFailed => {
            switch (stdout_writer.err.?) {
                // Assume the other side has closed the pipe and just exit early.
                // Otherwise, you'd get an ugly error if you did something like
                // this:
                //
                // $ echo "foo\nbar\nbaz" | zimilar-sort bar | head -n 1
                //
                error.BrokenPipe => std.process.exit(141),
                else => {
                    std.log.err("Error writing to stdout: {}\n", .{err});
                    process.exit(1);
                },
            }
        },
    };

    try stdout.flush();
}

/// Collects lines and sorts them by their Levenshtein distance to a needle.
///
/// Distances are computed as lines arrive. `myers.Matcher` can only process
/// lines of equal length, and only pays off when several are handled at once,
/// so equal-length lines are buffered until a full group is available.
const Sorter = struct {
    const Self = @This();

    /// Number of lines the bit-parallel matcher handles at once.
    const lanes = myers.Matcher.lanes;
    /// Longest line worth buffering for the batched matcher. Longer lines are
    /// matched on their own. The buffers below are indexed by line length, so
    /// this also bounds their size; it comfortably covers file paths.
    const max_batched_len = 256;
    allocator: Allocator,
    needle: []const u8,
    /// Null when the needle is too long to fit in the bit-parallel matcher.
    matcher: ?myers.Matcher,
    /// Scratch space for `levenshtein.distance`, used only when `matcher` is
    /// null. Empty otherwise.
    fallback_cache: []usize,
    lines: ArrayList(Line),
    /// Buffered lines of each length, waiting for a full group.
    pending: [max_batched_len + 1][lanes][]const u8 = undefined,
    /// Where each pending line belongs in `lines`.
    pending_at: [max_batched_len + 1][lanes]u32 = undefined,
    pending_count: [max_batched_len + 1]u8 = [_]u8{0} ** (max_batched_len + 1),

    fn init(allocator: Allocator, needle: []const u8, capacity: usize) !Self {
        const bit_parallel = needle.len > 0 and needle.len <= myers.Matcher.max_needle_len;
        return .{
            .allocator = allocator,
            .needle = needle,
            .matcher = if (bit_parallel) myers.Matcher.init(needle) else null,
            .fallback_cache = try allocator.alloc(usize, if (bit_parallel) 0 else needle.len),
            .lines = try ArrayList(Line).initCapacity(allocator, capacity),
        };
    }

    fn deinit(self: *Self) void {
        self.allocator.free(self.fallback_cache);
        self.lines.deinit(self.allocator);
    }

    /// Adds a line to be sorted. Empty lines are ignored.
    fn add(self: *Self, line: []const u8) !void {
        if (line.len == 0) return;

        const at: u32 = @intCast(self.lines.items.len);
        try self.lines.append(self.allocator, .{ .chars = line, .distance = undefined });

        if (self.needle.len == 0) {
            self.lines.items[at].distance = line.len;
        } else if (self.needle.len == 1) {
            // A one character needle either matches somewhere in the line or
            // has to be substituted for one of its characters, so the distance
            // is just the line length, less one if the character is present.
            const present = std.mem.indexOfScalar(u8, line, self.needle[0]) != null;
            self.lines.items[at].distance = line.len - @as(usize, @intFromBool(present));
        } else if (self.matcher) |*matcher| {
            if (line.len <= max_batched_len) {
                self.addBatched(matcher, line, at);
            } else {
                self.lines.items[at].distance = matcher.distance(line);
            }
        } else {
            self.lines.items[at].distance =
                levenshtein.distance(self.fallback_cache, self.needle, line);
        }
    }

    fn addBatched(self: *Self, matcher: *const myers.Matcher, line: []const u8, at: u32) void {
        const len = line.len;
        const n = self.pending_count[len];
        self.pending[len][n] = line;
        self.pending_at[len][n] = at;

        if (n + 1 < lanes) {
            self.pending_count[len] = n + 1;
            return;
        }

        var distances: [lanes]usize = undefined;
        matcher.distanceMany(&self.pending[len], &distances);
        for (self.pending_at[len], distances) |i, d| self.lines.items[i].distance = d;
        self.pending_count[len] = 0;
    }

    /// Flushes buffered lines, drops lines identical to the needle, and sorts
    /// the rest by ascending distance.
    fn sort(self: *Self) []Line {
        self.flushPending();

        // Compacting in place keeps the surviving lines in their original
        // relative order.
        var kept: usize = 0;
        for (self.lines.items) |line| {
            if (line.distance != 0) {
                self.lines.items[kept] = line;
                kept += 1;
            }
        }
        self.lines.shrinkRetainingCapacity(kept);

        std.sort.pdq(Line, self.lines.items, {}, Line.lessThan);
        return self.lines.items;
    }

    fn flushPending(self: *Self) void {
        const matcher = if (self.matcher) |*matcher| matcher else return;

        for (0..max_batched_len + 1) |len| {
            for (0..self.pending_count[len]) |n| {
                const at = self.pending_at[len][n];
                self.lines.items[at].distance = matcher.distance(self.pending[len][n]);
            }
        }
    }
};

const Line = struct {
    const Self = @This();

    chars: []const u8,
    distance: usize,

    fn lessThan(_: void, left: Self, right: Self) bool {
        return left.distance < right.distance;
    }
};

test "sort by distance" {
    const t = std.testing;

    var sorter = try Sorter.init(t.allocator, "hello", 0);
    defer sorter.deinit();

    // The four 5-byte lines fill a batch; the 7-byte line is matched alone.
    var it = std.mem.tokenizeAny(u8, "cello\njello\nhells\nhello\nworldly", "\n");
    while (it.next()) |line| try sorter.add(line);

    const sorted = sorter.sort();

    // "hello" is an exact match and is dropped.
    try t.expectEqual(4, sorted.len);
    try t.expectEqual(1, sorted[0].distance);
    try t.expectEqual(1, sorted[1].distance);
    try t.expectEqual(1, sorted[2].distance);
    try t.expectEqualStrings("worldly", sorted[3].chars);
}

test "long needles fall back to the scalar implementation" {
    const t = std.testing;

    const needle = "z" ** 70;
    var sorter = try Sorter.init(t.allocator, needle, 0);
    defer sorter.deinit();

    const input = "z\nzz\n" ++ ("z" ** 69);
    var it = std.mem.tokenizeAny(u8, input, "\n");
    while (it.next()) |line| try sorter.add(line);

    const sorted = sorter.sort();
    try t.expectEqual(3, sorted.len);
    try t.expectEqual(1, sorted[0].distance);
    try t.expectEqual(68, sorted[1].distance);
    try t.expectEqual(69, sorted[2].distance);
}

test "single character needle" {
    const t = std.testing;

    var sorter = try Sorter.init(t.allocator, "a", 0);
    defer sorter.deinit();

    var it = std.mem.tokenizeAny(u8, "a\nba\nbb\naaa", "\n");
    while (it.next()) |line| try sorter.add(line);

    const sorted = sorter.sort();

    // "a" is an exact match and is dropped.
    try t.expectEqual(3, sorted.len);
    try t.expectEqualStrings("ba", sorted[0].chars);
    try t.expectEqual(1, sorted[0].distance);
    try t.expectEqual(2, sorted[1].distance);
    try t.expectEqual(2, sorted[2].distance);
}

test {
    std.testing.refAllDecls(@This());
}
