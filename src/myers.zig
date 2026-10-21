const std = @import("std");

/// Bit-parallel Levenshtein distance, following Myers' algorithm as described
/// by Hyyrö:
///
///   https://www.cs.helsinki.fi/u/tpkarkka/opetus/13s/spa/lecture03.pdf
///
/// The needle is fixed for the whole run, so the per-character position
/// bitmasks are built once and reused for every line. Each line is then
/// processed with O(line.len) word-sized operations instead of the
/// O(needle.len * line.len) scalar dynamic program.
pub const Matcher = struct {
    /// Number of lines `distanceMany` processes at once. Eight 64-bit lanes
    /// fill a single AVX-512 register (or two AVX2 registers), which is enough
    /// to hide the loop-carried latency; wider batches measured slower.
    pub const lanes = 8;

    /// A single 64-bit word holds the needle, so it can be at most this long.
    pub const max_needle_len = 64;

    /// peq[c] has bit `i` set when `needle[i] == c`.
    peq: [256]u64,
    needle_len: u32,

    /// Requires `needle.len` in `1..max_needle_len`.
    pub fn init(needle: []const u8) Matcher {
        std.debug.assert(needle.len > 0 and needle.len <= max_needle_len);

        var peq = [_]u64{0} ** 256;
        for (needle, 0..) |c, i| {
            peq[c] |= @as(u64, 1) << @intCast(i);
        }
        return .{ .peq = peq, .needle_len = @intCast(needle.len) };
    }

    pub fn distance(self: *const Matcher, text: []const u8) usize {
        const shift: u6 = @intCast(self.needle_len - 1);

        var pv: u64 = ~@as(u64, 0);
        var mv: u64 = 0;
        var score: usize = self.needle_len;

        for (text) |c| {
            const eq = self.peq[c];
            const xv = eq | mv;
            const xh = (((eq & pv) +% pv) ^ pv) | eq;
            const ph = mv | ~(xh | pv);
            const mh = pv & xh;

            // Branchless score update: both conditions are data dependent and
            // mispredict often when written as branches.
            score +%= @intCast((ph >> shift) & 1);
            score -%= @intCast((mh >> shift) & 1);

            const ph_s = (ph << 1) | 1;
            pv = (mh << 1) | ~(xv | ph_s);
            mv = ph_s & xv;
        }

        return score;
    }

    /// Computes the distance to `lanes` texts at once, one per SIMD lane.
    ///
    /// The recurrence above is a long chain of dependent ALU operations, so a
    /// single text leaves most of the CPU's execution units idle. Advancing
    /// independent texts in lockstep fills that latency. All the texts must
    /// have the same length.
    pub fn distanceMany(
        self: *const Matcher,
        texts: *const [lanes][]const u8,
        out: *[lanes]usize,
    ) void {
        const shift: u6 = @intCast(self.needle_len - 1);
        const V = @Vector(lanes, u64);
        const ones: V = @splat(1);

        var pv: V = @splat(~@as(u64, 0));
        var mv: V = @splat(0);
        var score: V = @splat(@as(u64, self.needle_len));

        for (0..texts[0].len) |j| {
            var eq: V = undefined;
            inline for (0..lanes) |k| eq[k] = self.peq[texts[k][j]];

            const xv = eq | mv;
            const xh = (((eq & pv) +% pv) ^ pv) | eq;
            const ph = mv | ~(xh | pv);
            const mh = pv & xh;

            score +%= (ph >> @splat(shift)) & ones;
            score -%= (mh >> @splat(shift)) & ones;

            const ph_s = (ph << @splat(1)) | ones;
            pv = (mh << @splat(1)) | ~(xv | ph_s);
            mv = ph_s & xv;
        }

        inline for (0..lanes) |k| out[k] = score[k];
    }
};

const t = std.testing;

test "matches the scalar implementation" {
    const levenshtein = @import("levenshtein.zig");

    var prng = std.Random.DefaultPrng.init(0xdeadbeef);
    const rand = prng.random();

    var cache: [128]usize = undefined;
    var needle_buf: [16]u8 = undefined;
    var text_bufs: [Matcher.lanes][24]u8 = undefined;

    var needle_len: usize = 1;
    while (needle_len <= 6) : (needle_len += 1) {
        var text_len: usize = 0;
        while (text_len <= 8) : (text_len += 1) {
            var trial: usize = 0;
            while (trial < 200) : (trial += 1) {
                for (needle_buf[0..needle_len]) |*c| c.* = 'a' + rand.uintLessThan(u8, 3);
                for (&text_bufs) |*buf| {
                    for (buf[0..text_len]) |*c| c.* = 'a' + rand.uintLessThan(u8, 3);
                }
                const needle = needle_buf[0..needle_len];

                var texts: [Matcher.lanes][]const u8 = undefined;
                for (&texts, 0..) |*text, k| text.* = text_bufs[k][0..text_len];

                const matcher = Matcher.init(needle);
                var batched: [Matcher.lanes]usize = undefined;
                matcher.distanceMany(&texts, &batched);

                for (texts, batched) |text, got| {
                    const want = levenshtein.distance(&cache, needle, text);
                    try t.expectEqual(want, got);
                    try t.expectEqual(want, matcher.distance(text));
                }
            }
        }
    }
}
