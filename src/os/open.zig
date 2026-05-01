const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const build_config = @import("../build_config.zig");
const apprt = @import("../apprt.zig");

const log = std.log.scoped(.@"os-open");

/// Open a URL in the default handling application.
///
/// Any output on stderr is logged as a warning in the application logs.
/// Output on stdout is ignored. The allocator is used to buffer the
/// log output and may allocate from another thread.
///
/// This function is purposely simple for the sake of providing
/// some portable way to open URLs. If you are implementing an
/// apprt for Ghostty, you should consider doing something special-cased
/// for your platform.
pub fn open(
    alloc: Allocator,
    kind: apprt.action.OpenUrl.Kind,
    url: []const u8,
) !void {
    const argv: []const []const u8 = switch (builtin.os.tag) {
        .linux, .freebsd => &.{ "xdg-open", url },
        .windows => &.{ "rundll32", "url.dll,FileProtocolHandler", url },
        .macos => switch (kind) {
            .text => &.{ "open", "-t", url },
            .html, .unknown => &.{ "open", url },
        },
        .ios => return error.Unimplemented,
        else => @compileError("unsupported OS"),
    };

    // Pipe stdout/stderr so we can collect output from the command.
    var snap_env: std.process.Environ.Map = if (comptime build_config.snap) blk: {
        var env = try std.process.getEnvMap(alloc);
        env.remove("LD_LIBRARY_PATH");
        break :blk env;
    } else undefined;
    defer if (comptime build_config.snap) snap_env.deinit();

    const io = std.Io.Threaded.global_single_threaded.io();
    const exe = try std.process.spawn(io, .{
        .argv = argv,
        .stdin = .inherit,
        .stdout = .pipe,
        .stderr = .pipe,
        .environ_map = if (comptime build_config.snap) &snap_env else null,
    });

    // Create a thread that handles collecting output and reaping
    // the process. This is done in a separate thread because SOME
    // open implementations block and some do not. It's easier to just
    // spawn a thread to handle this so that we never block.
    const thread = try std.Thread.spawn(.{}, openThread, .{ alloc, exe });
    thread.detach();
}

fn openThread(alloc: Allocator, exe_: std.process.Child) !void {
    // 50 KiB is the default value used by std.process.run and should
    // be enough to get the output we care about.
    const output_max_size = 50 * 1024;
    const io = std.Io.Threaded.global_single_threaded.io();

    // Copy the exe so it is non-const. This is necessary because wait()
    // requires a mutable reference and we can't have one as a thread
    // param.
    var exe = exe_;
    defer exe.kill(io);

    var multi_reader_buffer: std.Io.File.MultiReader.Buffer(2) = undefined;
    var multi_reader: std.Io.File.MultiReader = undefined;
    multi_reader.init(alloc, io, multi_reader_buffer.toStreams(), &.{ exe.stdout.?, exe.stderr.? });
    defer multi_reader.deinit();

    const stdout_reader = multi_reader.reader(0);
    const stderr_reader = multi_reader.reader(1);

    while (multi_reader.fill(output_max_size, .none)) |_| {
        if (stdout_reader.buffered().len > output_max_size or
            stderr_reader.buffered().len > output_max_size) break;
    } else |err| switch (err) {
        error.EndOfStream => {},
        else => |e| return e,
    }

    try multi_reader.checkAnyError();
    _ = try exe.wait(io);

    const stderr = try multi_reader.toOwnedSlice(1);
    defer alloc.free(stderr);

    // If we have any stderr output we log it. This makes it easier for
    // users to debug why some open commands may not work as expected.
    if (stderr.len > 0) log.warn("wait stderr={s}", .{stderr});
}
