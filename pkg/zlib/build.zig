const std = @import("std");

/// Detect Xcode SDK path dynamically
fn detectXcodeSDKPath(allocator: std.mem.Allocator) ![]const u8 {
    // First try to get the path from xcode-select
    const result = std.process.run(allocator, std.Io.Threaded.global_single_threaded.io(), .{
        .argv = &[_][]const u8{ "xcode-select", "--print-path" },
    }) catch {
        // xcode-select failed, fall back to default path
        const default_path = "/Applications/Xcode.app/Contents/Developer";
        const sdk_path = try std.fmt.allocPrint(allocator, "{s}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk", .{default_path});
        return sdk_path;
    };
    defer allocator.free(result.stdout);

    // Trim whitespace from the output
    const xcode_path = std.mem.trim(u8, result.stdout, "\n\r ");

    // Construct the SDK path
    const sdk_path = try std.fmt.allocPrint(allocator, "{s}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk", .{xcode_path});

    // Verify the SDK path exists
    var dir = std.Io.Dir.openDir(std.Io.Dir.cwd(), std.Io.failing, sdk_path, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            // SDK not found, try to find available SDKs
            const platforms_path = try std.fmt.allocPrint(allocator, "{s}/Platforms/MacOSX.platform/Developer/SDKs", .{xcode_path});
            defer allocator.free(platforms_path);

            var platforms_dir = std.Io.Dir.openDir(std.Io.Dir.cwd(), std.Io.failing, platforms_path, .{}) catch {
                // If platforms directory doesn't exist, fall back to default
                allocator.free(sdk_path);
                const default_path = "/Applications/Xcode.app/Contents/Developer";
                const fallback_sdk_path = try std.fmt.allocPrint(allocator, "{s}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk", .{default_path});
                return fallback_sdk_path;
            };
            defer platforms_dir.close(std.Io.failing);

            // Look for the first available SDK
            var iterator = platforms_dir.iterate();
            while (try iterator.next(std.Io.failing)) |entry| {
                if (entry.kind == .directory and std.mem.startsWith(u8, entry.name, "MacOSX")) {
                    allocator.free(sdk_path);
                    const found_sdk_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ platforms_path, entry.name });
                    return found_sdk_path;
                }
            }

            // No SDK found, fall back to default
            allocator.free(sdk_path);
            const default_path = "/Applications/Xcode.app/Contents/Developer";
            const fallback_sdk_path = try std.fmt.allocPrint(allocator, "{s}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk", .{default_path});
            return fallback_sdk_path;
        },
        else => return err,
    };
    dir.close(std.Io.failing);

    return sdk_path;
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addLibrary(.{
        .name = "z",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
        .linkage = .static,
    });

    if (target.result.os.tag.isDarwin()) {
        const apple_sdk = @import("apple_sdk");
        try apple_sdk.addPaths(b, lib);
        // Enhanced system library linking for Zig 0.16.0 compatibility
        lib.root_module.linkSystemLibrary("c", .{ .use_pkg_config = .no });
        // Add Xcode SDK include paths for Zig 0.16.0 compatibility
        const sdk_path = detectXcodeSDKPath(b.allocator) catch
            "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk";
        const include_path = std.fmt.allocPrint(b.allocator, "{s}/usr/include", .{sdk_path}) catch unreachable;
        lib.root_module.addSystemIncludePath(.{ .cwd_relative = include_path });
        lib.root_module.addIncludePath(.{ .cwd_relative = "/usr/local/include" });
    } else {
        // Enhanced system library linking for cross-compilation
        lib.root_module.linkSystemLibrary("c", .{});
        lib.root_module.addIncludePath(.{ .cwd_relative = "/usr/include" });
        lib.root_module.addIncludePath(.{ .cwd_relative = "/usr/local/include" });
    }

    // Add additional system library linking for cross-compilation
    if (!target.query.isNative() and target.result.os.tag.isDarwin()) {
        lib.root_module.linkSystemLibrary("c", .{});
        const sdk_path_cross = detectXcodeSDKPath(b.allocator) catch
            "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk";
        const include_path_cross = std.fmt.allocPrint(b.allocator, "{s}/usr/include", .{sdk_path_cross}) catch unreachable;
        lib.root_module.addSystemIncludePath(.{ .cwd_relative = include_path_cross });
        lib.root_module.addIncludePath(.{ .cwd_relative = "/usr/local/include" });
    }

    if (b.lazyDependency("zlib", .{})) |upstream| {
        lib.root_module.addIncludePath(upstream.path(""));
        lib.installHeadersDirectory(
            upstream.path(""),
            "",
            .{ .include_extensions = &.{".h"} },
        );

        var flags: std.ArrayList([]const u8) = .empty;
        defer flags.deinit(b.allocator);
        try flags.appendSlice(b.allocator, &.{
            "-DHAVE_SYS_TYPES_H",
            "-DHAVE_STDINT_H",
            "-DHAVE_STDDEF_H",
        });
        if (target.result.abi == .msvc) {
            try flags.appendSlice(b.allocator, &.{
                "-fno-sanitize=undefined",
                "-fno-sanitize-trap=undefined",
            });
        }
        if (target.result.os.tag != .windows) {
            try flags.append(b.allocator, "-DZ_HAVE_UNISTD_H");
        }
        if (target.result.abi == .msvc) {
            try flags.appendSlice(b.allocator, &.{
                "-D_CRT_SECURE_NO_DEPRECATE",
                "-D_CRT_NONSTDC_NO_DEPRECATE",
            });
        }
        inline for (srcs) |file| {
            lib.root_module.addCSourceFile(.{ .file = upstream.path(file), .flags = flags.items });
        }
    }

    b.installArtifact(lib);
}

const srcs: []const []const u8 = &.{
    "adler32.c",
    "compress.c",
    "crc32.c",
    "deflate.c",
    "gzclose.c",
    "gzlib.c",
    "gzread.c",
    "gzwrite.c",
    "inflate.c",
    "infback.c",
    "inftrees.c",
    "inffast.c",
    "trees.c",
    "uncompr.c",
    "zutil.c",
};
