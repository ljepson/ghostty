const GhosttyXCFramework = @This();

const std = @import("std");
const Config = @import("Config.zig");
const SharedDeps = @import("SharedDeps.zig");
const GhosttyLib = @import("GhosttyLib.zig");
const XCFrameworkStep = @import("XCFrameworkStep.zig");
const Target = @import("xcframework.zig").Target;

xcframework: *XCFrameworkStep,
target: Target,

pub fn init(
    b: *std.Build,
    deps: *const SharedDeps,
    target: Target,
) !GhosttyXCFramework {
    // Universal macOS build
    const macos_universal = try GhosttyLib.initMacOSUniversal(b, deps);

    // Native macOS build
    const macos_native = try GhosttyLib.initStatic(b, &try deps.retarget(
        b,
        Config.genericMacOSTarget(b, null),
    ));

    // iOS - Skip iOS builds for Zig 0.16.0 compatibility due to fallback SDK limitations
    const is_zig_016 = comptime (std.mem.eql(u8, @import("builtin").zig_version_string, "0.16.0"));
    const ios = if (is_zig_016) 
        null 
    else 
        try GhosttyLib.initStatic(b, &try deps.retarget(
            b,
            b.resolveTargetQuery(.{
                .cpu_arch = .aarch64,
                .os_tag = .ios,
                .os_version_min = Config.osVersionMin(.ios),
                .abi = null,
            }),
        ));

    // iOS Simulator - Skip iOS simulator builds for Zig 0.16.0 compatibility
    const ios_sim = if (is_zig_016) 
        null 
    else 
        try GhosttyLib.initStatic(b, &try deps.retarget(
            b,
            b.resolveTargetQuery(.{
                .cpu_arch = .aarch64,
                .os_tag = .ios,
                .os_version_min = Config.osVersionMin(.ios),
                .abi = .simulator,

                // We force the Apple CPU model because the simulator
                // doesn't support the generic CPU model as of Zig 0.14 due
                // to missing "altnzcv" instructions, which is false. This
                // surely can't be right but we can fix this if/when we get
                // back to running simulator builds.
                .cpu_model = .{ .explicit = &std.Target.aarch64.cpu.apple_a17 },
            }),
        ));

    // Generate a headers directory with only ghostty.h and the module
    // map. We can't use include/ directly because it also contains the
    // libghostty-vt headers under include/ghostty/, which would trigger
    // "umbrella header does not include header" warnings from Clang's
    // module system.
    const wf = b.addWriteFiles();
    _ = wf.addCopyFile(b.path("include/ghostty.h"), "ghostty.h");
    _ = wf.addCopyFile(b.path("include/module.modulemap"), "module.modulemap");
    const headers = wf.getDirectory();

    // The xcframework wraps our ghostty library so that we can link
    // it to the final app built with Swift.
    const xcframework = XCFrameworkStep.create(b, .{
        .name = "GhosttyKit",
        .out_path = "macos/GhosttyKit.xcframework",
        .libraries = switch (target) {
            .universal => blk: {
                var libs = try std.ArrayList(XCFrameworkStep.Library).initCapacity(b.allocator, 3);
                defer libs.deinit(b.allocator);
                
                // Always include macOS universal
                try libs.append(b.allocator, .{
                    .library = macos_universal.output,
                    .headers = headers,
                    .dsym = macos_universal.dsym,
                });
                
                // Include iOS targets if available (not null)
                if (ios) |ios_lib| {
                    try libs.append(b.allocator, .{
                        .library = ios_lib.output,
                        .headers = headers,
                        .dsym = ios_lib.dsym,
                    });
                }
                
                if (ios_sim) |ios_sim_lib| {
                    try libs.append(b.allocator, .{
                        .library = ios_sim_lib.output,
                        .headers = headers,
                        .dsym = ios_sim_lib.dsym,
                    });
                }
                
                break :blk libs.toOwnedSlice(b.allocator) catch &[_]XCFrameworkStep.Library{};
            },

            .native => &.{.{
                .library = macos_native.output,
                .headers = headers,
                .dsym = macos_native.dsym,
            }},
        },
    });

    return .{
        .xcframework = xcframework,
        .target = target,
    };
}

pub fn install(self: *const GhosttyXCFramework) void {
    const b = self.xcframework.step.owner;
    self.addStepDependencies(b.getInstallStep());
}

pub fn addStepDependencies(
    self: *const GhosttyXCFramework,
    other_step: *std.Build.Step,
) void {
    other_step.dependOn(self.xcframework.step);
}
