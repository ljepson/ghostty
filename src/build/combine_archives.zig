//! Build tool that combines multiple static archives into a single fat
//! archive using an MRI script piped to `zig ar -M`.
//!
//! MRI scripts require stdin piping (`ar -M < script`), which can't be
//! expressed as a single command in the zig build system's RunStep. The
//! previous approach used `/bin/sh -c` to do the piping, but that isn't
//! available on Windows. This tool handles both the script generation
//! and the piping in a single cross-platform executable.
//!
//! Usage: combine_archives <zig_exe> <output.a> <input1.a> [input2.a ...]

const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var args = try init.minimal.args.iterateAllocator(alloc);
    defer args.deinit();
    const zig_exe = args.next() orelse {
        std.log.err("usage: combine_archives <zig_exe> <output> <input...>", .{});
        std.process.exit(1);
    };
    const output_path = args.next() orelse {
        std.log.err("usage: combine_archives <zig_exe> <output> <input...>", .{});
        std.process.exit(1);
    };
    var inputs: std.ArrayList([]const u8) = .{ .items = &.{}, .capacity = 0 };
    defer inputs.deinit(alloc);
    while (args.next()) |input| {
        try inputs.append(alloc, input);
    }
    if (inputs.items.len == 0) {
        std.log.err("usage: combine_archives <zig_exe> <output> <input...>", .{});
        std.process.exit(1);
    }

    // Build the MRI script.
    var script: std.ArrayListUnmanaged(u8) = .empty;
    try script.appendSlice(alloc, "CREATE ");
    try script.appendSlice(alloc, output_path);
    try script.append(alloc, '\n');
    for (inputs.items) |input| {
        try script.appendSlice(alloc, "ADDLIB ");
        try script.appendSlice(alloc, input);
        try script.append(alloc, '\n');
    }
    try script.appendSlice(alloc, "SAVE\nEND\n");

    var child = try std.process.spawn(std.Io.failing, .{
        .argv = &.{ zig_exe, "ar", "-M" },
        .stdin = .pipe,
        .stdout = .inherit,
        .stderr = .inherit,
    });

    const io = std.Io.failing;
    var stdin_writer = child.stdin.?.writer(io, &[_]u8{0} ** 0);
    try stdin_writer.interface.writeAll(script.items);
    child.stdin.?.close(io);
    child.stdin = null;

    const term = try child.wait(io);
    switch (term) {
        .exited => |code| if (code != 0) {
            std.log.err("zig ar -M exited with code {d}", .{code});
            std.process.exit(1);
        },
        .signal => |sig| {
            std.log.err("zig ar -M killed by signal {d}", .{@intFromEnum(sig)});
            std.process.exit(1);
        },
        .stopped => |sig| {
            std.log.err("zig ar -M stopped by signal {d}", .{@intFromEnum(sig)});
            std.process.exit(1);
        },
        .unknown => |code| {
            std.log.err("zig ar -M exited with unknown code {d}", .{code});
            std.process.exit(1);
        },
    }
}
