const std = @import("std");

pub fn BST(comptime T: type, comptime cmp: fn (T, T) std.math.Order) type {
    return struct {
        val: T,
        left: ?*@This(),
        right: ?*@This(),
        alloc: std.mem.Allocator,

        pub fn init(val: T, alloc: std.mem.Allocator) !*@This() {
            const node = try alloc.create(BST(T, cmp));
            node.* = .{ .val = val, .left = null, .right = null, .alloc = alloc };
            return node;
        }

        pub fn deinit(self: *@This()) void {
            if (self.left) |l| l.deinit();
            if (self.right) |r| r.deinit();
            self.alloc.destroy(self);
        }

        pub fn traverse(self: *@This(), v: *std.array_list.Managed(T)) !void {
            if (self.left) |l| try l.traverse(v);
            try v.append(self.val);
            if (self.right) |r| try r.traverse(v);
        }

        pub fn insert(self: *@This(), val: T) !void {
            switch (cmp(val, self.val)) {
                .eq => return,
                .lt => {
                    if (self.left) |l| {
                        try l.insert(val);
                    } else {
                        const node = try self.alloc.create(BST(T, cmp));
                        node.* = .{ .val = val, .left = null, .right = null, .alloc = self.alloc };
                        self.left = node;
                    }
                },
                .gt => {
                    if (self.right) |r| {
                        try r.insert(val);
                    } else {
                        const node = try self.alloc.create(BST(T, cmp));
                        node.* = .{ .val = val, .left = null, .right = null, .alloc = self.alloc };
                        self.right = node;
                    }
                },
            }
        }
    };
}

fn orderI32(a: i32, b: i32) std.math.Order {
    return std.math.order(a, b);
}

test "bst_insert" {
    const bst = try BST(i32, orderI32).init(2, std.testing.allocator);
    defer bst.deinit();

    try bst.insert(1);
    try bst.insert(3);
    try bst.insert(0);
    try bst.insert(4);

    var expected_traversal = std.array_list.Managed(i32).init(std.testing.allocator);
    defer expected_traversal.deinit();
    try expected_traversal.appendSlice(&.{ 0, 1, 2, 3, 4 });
    var actual_traversal = std.array_list.Managed(i32).init(std.testing.allocator);
    defer actual_traversal.deinit();
    try bst.traverse(&actual_traversal);

    try std.testing.expectEqualSlices(i32, expected_traversal.items, actual_traversal.items);
}
