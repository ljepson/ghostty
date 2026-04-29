const std = @import("std");

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
        // Add system include paths for Zig 0.16.0 fallback SDK
        lib.root_module.addIncludePath(b.path("/usr/include"));
        lib.root_module.addIncludePath(b.path("/usr/local/include"));
    } else {
        // Enhanced system library linking for cross-compilation
        lib.root_module.linkSystemLibrary("c", .{});
        lib.root_module.addIncludePath(b.path("/usr/include"));
        lib.root_module.addIncludePath(b.path("/usr/local/include"));
    }
    
    // Add additional system library linking for cross-compilation
    if (!target.query.isNative()) {
        lib.root_module.linkSystemLibrary("c", .{});
        lib.root_module.addIncludePath(b.path("/usr/include"));
        lib.root_module.addIncludePath(b.path("/usr/local/include"));
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
