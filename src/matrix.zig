const std = @import("std");
const Allocator = std.mem.Allocator;

const Self = @This();

allocator: Allocator,
data: []usize,
height: usize,
width: usize,

pub fn init(allocator: Allocator, height: usize, width: usize) !Self {
    const data = try allocator.alloc(usize, height * width);

    return Self{ .allocator = allocator, .data = data, .height = height, .width = width };
}

pub fn deinit(self: Self) void {
    self.allocator.free(self.data);
}

pub fn get(self: Self, x: usize, y: usize) usize {
    return self.data[self.index(x, y)];
}

pub fn set(self: *Self, x: usize, y: usize, value: usize) void {
    self.data[self.index(x, y)] = value;
}

fn index(self: Self, x: usize, y: usize) usize {
    return self.height * y + x;
}

const t = std.testing;

test "init" {
    const matrix = try Self.init(t.allocator, 2, 2);
    defer matrix.deinit();
}

test "accessors" {
    var matrix = try Self.init(t.allocator, 2, 2);
    defer matrix.deinit();

    matrix.set(0, 1, 50);
    try t.expectEqual(@as(usize, 50), matrix.get(0, 1));

    matrix.set(0, 1, 25);
    try t.expectEqual(@as(usize, 25), matrix.get(0, 1));
}
