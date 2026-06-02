//! By convention, root.zig is the root source file when making a package.
const std = @import("std");
const Io = std.Io;

pub fn Node(comptime T: type) type {
    return struct {
        val: T,
        next: ?*@This(),
    };
}

pub fn LinkedList(comptime T: type) type {
    const NodeT = Node(T);
    return struct {
        head: ?*NodeT,
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) @This() {
            return .{ .head = null, .allocator = allocator };
        }

        pub fn deinit(self: *@This()) void {
            var cur = self.head;
            while (cur) |n| {
                cur = n.next;
                self.allocator.destroy(n);
            }
        }

        pub fn push(self: *@This(), val: i32) !void {
            const node = try self.allocator.create(NodeT);
            node.* = .{ .val = val, .next = self.head };
            self.head = node;
        }
    };
}

test "append_i32" {
    var l = LinkedList(i32).init(std.testing.allocator);
    defer l.deinit();

    try l.push(1);
    try l.push(2);
    try l.push(3);

    var cur = l.head;
    while (cur) |n| : (cur = n.next) {
        std.debug.print("val = {d}\n", .{n.val});
    }
}

test "append_f64" {
    var l = LinkedList(f64).init(std.testing.allocator);
    defer l.deinit();

    try l.push(1.0);
    try l.push(2.0);
    try l.push(3.0);

    var cur = l.head;
    while (cur) |n| : (cur = n.next) {
        std.debug.print("val = {d}\n", .{n.val});
    }
}
