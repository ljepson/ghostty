const std = @import("std");
const linux = std.os.linux;

const log = std.log.scoped(.@"linux-cgroup");

/// Returns the path to the cgroup for the given pid.
pub fn current(buf: []u8, pid: u32) ?[]const u8 {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;

    // Read our cgroup by opening /proc/<pid>/cgroup and reading the first
    // line. The first line will look something like this:
    // 0::/user.slice/user-1000.slice/session-1.scope
    // The cgroup path is the third field.
    const path = std.fmt.bufPrintZ(&path_buf, "/proc/{}/cgroup", .{pid}) catch return null;
    const fd_raw = linux.openat(linux.AT.FDCWD, path, linux.O{}, 0);
    switch (linux.errno(fd_raw)) {
        .SUCCESS => {},
        else => return null,
    }

    const fd: linux.fd_t = @intCast(fd_raw);
    defer _ = linux.close(fd);

    var read_buf: [64]u8 = undefined;
    var file = std.Io.File{ .handle = fd, .flags = .{ .nonblocking = false } };
    const io = std.Io.Threaded.global_single_threaded.io();
    var file_reader = file.reader(io, &read_buf);
    const reader = &file_reader.interface;
    const len = reader.readSliceShort(buf) catch return null;
    const contents = buf[0..len];

    // Find the last ':'
    const idx = std.mem.lastIndexOfScalar(u8, contents, ':') orelse return null;
    return std.mem.trimEnd(u8, contents[idx + 1 ..], " \r\n");
}
