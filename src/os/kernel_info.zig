const std = @import("std");
const builtin = @import("builtin");

pub fn getKernelInfo(alloc: std.mem.Allocator) ?[]const u8 {
    if (comptime builtin.os.tag != .linux) return null;
    const path = "/proc/sys/kernel/osrelease";
    const io = std.Io.Threaded.global_single_threaded.io();
    var file = std.Io.Dir.openFileAbsolute(io, path, .{}) catch return null;
    defer file.close(io);

    // 128 bytes should be enough to hold the kernel information
    var buf: [128]u8 = undefined;
    var reader = file.reader(io, &buf);
    const kernel_info = reader.interface.allocRemaining(alloc, .limited(128)) catch return null;
    defer alloc.free(kernel_info);
    return alloc.dupe(u8, std.mem.trim(u8, kernel_info, &std.ascii.whitespace)) catch return null;
}

test "read /proc/sys/kernel/osrelease" {
    if (comptime builtin.os.tag != .linux) return null;
    const allocator = std.testing.allocator;

    const kernel_info = getKernelInfo(allocator).?;
    defer allocator.free(kernel_info);

    // Since we can't hardcode the info in tests, just check
    // if something was read from the file
    try std.testing.expect(kernel_info.len > 0);
    try std.testing.expect(!std.mem.eql(u8, kernel_info, ""));
}
