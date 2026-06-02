const std = @import("std");
const Io = std.Io;

const RingBufferError = error{
    BufferFull,
    BufferEmpty,
};

pub fn SPCS(comptime T: type) type {
    return struct {
        cap: i32,
        read_idx: usize,
        write_idx: usize,
        allocator: std.mem.Allocator,
        data: []T,

        pub fn init(cap: i32, alloc: std.mem.Allocator) !@This() {
            const data = try alloc.alloc(T, @as(usize, 1) << @intCast(cap));
            return .{ .cap = cap, .read_idx = 0, .write_idx = 0, .data = data, .allocator = alloc };
        }

        pub fn deinit(self: *@This()) void {
            self.allocator.free(self.data);
        }

        pub fn push(self: *@This(), val: T) RingBufferError!void {
            const capacity = @as(usize, 1) << @intCast(self.cap);
            if (self.write_idx - self.read_idx == capacity) {
                return RingBufferError.BufferFull;
            }
            self.data[self.write_idx & (capacity - 1)] = val;
            self.write_idx += 1;
        }

        pub fn read(self: *@This()) RingBufferError!T {
            const capacity = @as(usize, 1) << @intCast(self.cap);
            if (self.read_idx == self.write_idx) {
                return RingBufferError.BufferEmpty;
            }
            const val = self.data[self.read_idx & (capacity - 1)];
            self.read_idx += 1;
            return val;
        }
    };
}

test "push read" {
    var scsp = try SPCS(i32).init(2, std.testing.allocator);
    defer scsp.deinit();

    try std.testing.expectError(RingBufferError.BufferEmpty, scsp.read());

    try scsp.push(1);

    try std.testing.expect(try scsp.read() == 1);

    try scsp.push(2);
    try scsp.push(3);
    try scsp.push(4);
    try scsp.push(5);

    try std.testing.expectError(RingBufferError.BufferFull, scsp.push(6));

    try std.testing.expect(try scsp.read() == 2);
    try std.testing.expect(try scsp.read() == 3);
    try std.testing.expect(try scsp.read() == 4);
    try std.testing.expect(try scsp.read() == 5);
}
