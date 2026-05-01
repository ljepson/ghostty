const std = @import("std");
const assert = @import("../quirks.zig").inlineAssert;
const Allocator = std.mem.Allocator;
const testing = std.testing;

/// A data structure where you can get stable (never copied) pointers to
/// a type that automatically grows if necessary. The values can be "put back"
/// but are expected to be put back IN ORDER.
///
/// This is implemented specifically for libuv write requests, since the
/// write requests must have a stable pointer and are guaranteed to be processed
/// in order for a single stream.
///
/// This is NOT thread safe.
pub fn SegmentedPool(comptime T: type, comptime prealloc: usize) type {
    return struct {
        const Self = @This();

        i: usize = 0,
        available: usize = prealloc,
        len: usize = prealloc,
        items: [prealloc]T = undefined,

        pub fn deinit(self: *Self, alloc: Allocator) void {
            // Only free if we grew beyond the initial allocation
            if (self.len > prealloc) {
                alloc.free(self.items.ptr[prealloc..self.len]);
            }
            self.* = undefined;
        }

        /// Get the next available value out of the list. This will not
        /// grow the list.
        pub fn get(self: *Self) !*T {
            if (self.available == 0) return error.OutOfValues;

            const idx = @mod(self.i, self.len);
            self.i +%= 1;
            self.available -= 1;
            return &self.items[idx];
        }

        /// Get the next available value out of the list and grow the list
        /// if necessary.
        pub fn getGrow(self: *Self, alloc: Allocator) !*T {
            if (self.available == 0) try self.grow(alloc);
            return try self.get();
        }

        fn grow(self: *Self, alloc: Allocator) !void {
            const new_len = self.len * 2;
            const new_items = try alloc.alloc(T, new_len);
            // Copy existing items
            @memcpy(new_items[0..self.len], self.items[0..self.len]);
            // Free old buffer if it was heap-allocated
            if (self.len > prealloc) {
                alloc.free(self.items.ptr[prealloc..self.len]);
            }
            self.items.ptr = new_items.ptr;
            self.len = new_len;
            self.i = self.len;
            self.available = self.len;
        }

        /// Put a value back. The value put back is expected to be the
        /// in order of get.
        pub fn put(self: *Self) void {
            self.available += 1;
            assert(self.available <= self.len);
        }
    };
}

test "SegmentedPool" {
    var list: SegmentedPool(u8, 2) = .{};
    defer list.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 2), list.available);

    // Get to capacity
    const v1 = try list.get();
    const v2 = try list.get();
    try testing.expect(v1 != v2);
    try testing.expectError(error.OutOfValues, list.get());

    // Test writing for later
    v1.* = 42;

    // Put a value back
    list.put();
    const temp = try list.get();
    try testing.expect(v1 == temp);
    try testing.expect(temp.* == 42);
    try testing.expectError(error.OutOfValues, list.get());

    // Grow
    const v3 = try list.getGrow(testing.allocator);
    try testing.expect(v1 != v3 and v2 != v3);
    _ = try list.get();
    try testing.expectError(error.OutOfValues, list.get());

    // Put a value back
    list.put();
    try testing.expect(v1 == try list.get());
    try testing.expectError(error.OutOfValues, list.get());
}