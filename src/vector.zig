//! By convention, root.zig is the root source file when making a package.
const std = @import("std");
const Io = std.Io;

pub fn Vector(comptime T: type) type {
    return struct {
        cap: usize,
        len: usize,
        allocator: std.mem.Allocator,
        data: []T,

        pub fn init(cap: usize, alloc: std.mem.Allocator) !@This() {
            const data = try alloc.alloc(T, cap);
            return .{ .cap = cap, .len = 0, .allocator = alloc, .data = data };
        }

        pub fn deinit(self: *@This()) void {
            self.allocator.free(self.data);
        }

        pub fn push(self: *@This(), val: T) !void {
            if (self.len == self.cap) {
                const new_data = try self.allocator.alloc(T, self.cap * 2);
                self.allocator.free(self.data);
                self.data = new_data;
                self.cap *= 2;
            }
            self.data[self.len] = val;
            self.len += 1;
        }
    };
}

test "array_list" {
    var al = try Vector(i32).init(3, std.testing.allocator);
    defer al.deinit();

    try (std.testing.expect(al.cap == 3));
    try (std.testing.expect(al.len == 0));

    for (1..4) |i| {
        const idx: i32 = @intCast(i);
        try al.push(idx);
        try std.testing.expect(al.data[i - 1] == idx);
        try std.testing.expect(al.len == idx);
    }

    try al.push(4);
    try std.testing.expect(al.len == 4);
    try std.testing.expect(al.cap == 6);
}
