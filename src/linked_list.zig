//! By convention, root.zig is the root source file when making a package.
const std = @import("std");
const Io = std.Io;

const Node = struct {
    val: i32,
    next: ?*Node,
};

const LinkedList = struct {
    head: ?*Node,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) LinkedList {
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
        const node = try self.allocator.create(Node);
        node.* = .{ .val = val, .next = self.head };
        self.head = node;
    }
};

test "append" {
    var l = LinkedList.init(std.testing.allocator);
    defer l.deinit();

    try l.push(1);
    try l.push(2);
    try l.push(3);

    var cur = l.head;
    while (cur) |n| : (cur = n.next) {
        std.debug.print("val = {d}\n", .{n.val});
    }
}
