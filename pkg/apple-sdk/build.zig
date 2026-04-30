const std = @import("std");
const builtin = @import("builtin");

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
    _ = target;
    _ = optimize;
}

/// Setup the step to point to the proper Apple SDK for libc and
/// frameworks. When running on a Darwin host, this uses the native
/// SDK installed on the system via `xcrun`. When cross-compiling from
/// a non-Darwin host, it falls back to Zig's bundled Darwin headers.
pub fn addPaths(
    b: *std.Build,
    step: *std.Build.Step.Compile,
) !void {
    // The cache. This always uses b.allocator and never frees memory
    // (which is idiomatic for a Zig build exe). We cache the libc txt
    // file we create because it is expensive to generate (subprocesses).
    const Cache = struct {
        const Key = struct {
            arch: std.Target.Cpu.Arch,
            os: std.Target.Os.Tag,
            abi: std.Target.Abi,
        };

        const Value = union(enum) {
            native: struct {
                libc: std.Build.LazyPath,
                framework: []const u8,
                system_include: []const u8,
                library: []const u8,
            },
            cross: struct {
                libc: std.Build.LazyPath,
            },
        };

        var map: std.AutoHashMapUnmanaged(Key, ?Value) = .{};
    };

    const target = step.rootModuleTarget();
    const gop = try Cache.map.getOrPut(b.allocator, .{
        .arch = target.cpu.arch,
        .os = target.os.tag,
        .abi = target.abi,
    });

    if (!gop.found_existing) init: {
        if (comptime builtin.os.tag.isDarwin()) {
            // Detect our SDK using the "findNative" Zig stdlib function.
            // This is really important because it forces using `xcrun` to
            // find the SDK path.
            // TODO: Fix LibCInstallation.findNative for Zig 0.16.0
            // Workaround for Zig 0.16.0 SDK detection issues
            var environ_map = std.process.Environ.Map.init(b.allocator);
            defer environ_map.deinit();
            const libc = blk: {
                // Detect Xcode SDK path dynamically for Zig 0.16.0 compatibility
                const sdk_path = detectXcodeSDKPath(b.allocator) catch 
                    "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk";
                const custom_libc = b.allocator.create(std.zig.LibCInstallation) catch unreachable;
                custom_libc.* = .{
                    .include_dir = std.fmt.allocPrint(b.allocator, "{s}/usr/include", .{sdk_path}) catch unreachable,
                    .sys_include_dir = std.fmt.allocPrint(b.allocator, "{s}/usr/include", .{sdk_path}) catch unreachable,
                    .crt_dir = std.fmt.allocPrint(b.allocator, "{s}/usr/lib", .{sdk_path}) catch unreachable,
                    .msvc_lib_dir = "",
                    .kernel32_lib_dir = "",
                    .gcc_dir = "",
                };
                break :blk custom_libc.*;
            };

            // Render the file compatible with the `--libc` Zig flag.
            var stream: std.Io.Writer.Allocating = .init(b.allocator);
            defer stream.deinit();
            try libc.render(&stream.writer);

            // Create a temporary file to store the libc path because
            // `--libc` expects a file path.
            const wf = b.addWriteFiles();
            const path = wf.add("libc.txt", stream.written());

            // Determine our framework path. Zig has a bug where it doesn't
            // parse this from the libc txt file for `-framework` flags:
            // https://github.com/ziglang/zig/issues/24024
            const framework_path = framework: {
                const down1 = std.fs.path.dirname(libc.sys_include_dir.?).?;
                const down2 = std.fs.path.dirname(down1).?;
                break :framework try std.fs.path.join(b.allocator, &.{
                    down2,
                    "System",
                    "Library",
                    "Frameworks",
                });
            };

            const library_path = library: {
                const down1 = std.fs.path.dirname(libc.sys_include_dir.?).?;
                break :library try std.fs.path.join(b.allocator, &.{
                    down1,
                    "lib",
                });
            };

            gop.value_ptr.* = .{ .native = .{
                .libc = path,
                .framework = framework_path,
                .system_include = libc.sys_include_dir.?,
                .library = library_path,
            } };

            break :init;
        }

        // Cross-compiling to Darwin from a non-Darwin host.
        // Zig only bundles macOS headers, so for other Apple platforms
        // we leave the value as null to produce a descriptive error.
        if (target.os.tag != .macos) {
            gop.value_ptr.* = null;
            break :init;
        }

        // Fall back to Zig's bundled Darwin headers for libc resolution.
        const zig_lib_path = b.graph.zig_lib_directory.path.?;
        const include_dir = b.pathJoin(&.{
            zig_lib_path, "libc", "include", "any-macos-any",
        });

        const wf = b.addWriteFiles();
        const path = wf.add("libc.txt", b.fmt(
            \\include_dir={s}
            \\sys_include_dir={s}
            \\crt_dir=
            \\msvc_lib_dir=
            \\kernel32_lib_dir=
            \\gcc_dir=
            \\
        , .{ include_dir, include_dir }));

        gop.value_ptr.* = .{ .cross = .{ .libc = path } };
    }

    const value = gop.value_ptr.* orelse return switch (target.os.tag) {
        // Return a more descriptive error. Before we just returned the
        // generic error but this was confusing a lot of community members.
        // It costs us nothing in the build script to return something better.
        .macos => error.XcodeMacOSSDKNotFound,
        .ios => error.XcodeiOSSDKNotFound,
        .tvos => error.XcodeTVOSSDKNotFound,
        .watchos => error.XcodeWatchOSSDKNotFound,
        else => error.XcodeAppleSDKNotFound,
    };

    switch (value) {
        .native => |native| {
            step.setLibCFile(native.libc);

            // This is only necessary until this bug is fixed:
            // https://github.com/ziglang/zig/issues/24024
            step.root_module.addSystemFrameworkPath(.{ .cwd_relative = native.framework });
            step.root_module.addSystemIncludePath(.{ .cwd_relative = native.system_include });
            step.root_module.addLibraryPath(.{ .cwd_relative = native.library });
        },
        .cross => |cross| {
            step.setLibCFile(cross.libc);
        },
    }
}
