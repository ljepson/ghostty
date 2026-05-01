const std = @import("std");
const builtin = @import("builtin");
const windows = @import("windows.zig");
const posix = std.posix;

/// pipe() that works on Windows and POSIX. For POSIX systems, this sets
/// CLOEXEC on the file descriptors.
pub fn pipe() ![2]posix.fd_t {
    switch (builtin.os.tag) {
        else => {
            var fds: [2]posix.fd_t = undefined;

            if (@TypeOf(posix.system.pipe2) != void) {
                switch (posix.errno(posix.system.pipe2(&fds, .{ .CLOEXEC = true }))) {
                    .SUCCESS => return fds,
                    else => |err| return posix.unexpectedErrno(err),
                }
            }

            switch (posix.errno(posix.system.pipe(&fds))) {
                .SUCCESS => {},
                else => |err| return posix.unexpectedErrno(err),
            }
            errdefer {
                _ = std.c.close(fds[0]);
                _ = std.c.close(fds[1]);
            }

            for (fds) |fd| {
                switch (posix.errno(posix.system.fcntl(fd, posix.F.SETFD, @as(u32, posix.FD_CLOEXEC)))) {
                    .SUCCESS => {},
                    else => |err| return posix.unexpectedErrno(err),
                }
            }

            return fds;
        },
        .windows => {
            var read: windows.HANDLE = undefined;
            var write: windows.HANDLE = undefined;
            if (windows.exp.kernel32.CreatePipe(&read, &write, null, 0) == 0) {
                return windows.unexpectedError(windows.kernel32.GetLastError());
            }

            return .{ read, write };
        },
    }
}
