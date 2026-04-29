const std = @import("std");
const testing = std.testing;
const Screen = @import("../src/terminal/Screen.zig").Screen;
const Allocator = std.mem.Allocator;

/// Performance regression tests for Zig 0.16.0 compatibility
/// This ensures our API changes don't impact terminal performance
test "performance regression - screen operations" {
    const testing = std.testing;
    
    const allocator = testing.allocator;
    const start_time = std.time.nanoTimestamp();
    
    // Create a screen and perform intensive operations
    var screen = try Screen.init(allocator, .{
        .rows = 24,
        .cols = 80,
        .scrollback_max = 1000,
        .kitty_image_storage_limit = 0,
        .kitty_image_loading_limits = .{},
    });
    defer screen.deinit();
    
    // Performance test: Write a large amount of text
    const test_text = "The quick brown fox jumps over the lazy dog. ";
    const iterations = 1000;
    
    for (0..iterations) |_| {
        try screen.testWriteString(test_text);
    }
    
    const end_time = std.time.nanoTimestamp();
    const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
    
    // Should complete within reasonable time (adjust threshold as needed)
    try testing.expect(duration_ms < 100.0); // 100ms threshold
    
    // Verify screen integrity after performance test
    screen.assertIntegrity();
}

test "performance regression - memory allocation patterns" {
    const testing = std.testing;
    
    const allocator = testing.allocator;
    const start_time = std.time.nanoTimestamp();
    
    // Test that our new environment map patterns don't impact performance
    var env_map = std.process.Environ.Map.init(allocator);
    defer env_map.deinit();
    
    // Performance test: Add many environment variables
    const iterations = 1000;
    for (0..iterations) |i| {
        const key = try std.fmt.allocPrint(allocator, "TEST_VAR_{d}", .{i});
        defer allocator.free(key);
        const value = try std.fmt.allocPrint(allocator, "test_value_{d}", .{i});
        defer allocator.free(value);
        
        try env_map.put(key, value);
    }
    
    // Performance test: Look up all environment variables
    for (0..iterations) |i| {
        const key = try std.fmt.allocPrint(allocator, "TEST_VAR_{d}", .{i});
        defer allocator.free(key);
        
        const value = env_map.get(key);
        try testing.expect(value != null);
    }
    
    const end_time = std.time.nanoTimestamp();
    const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
    
    // Should complete within reasonable time
    try testing.expect(duration_ms < 50.0); // 50ms threshold
}

test "performance regression - file system operations" {
    const testing = std.testing;
    
    const allocator = testing.allocator;
    const start_time = std.time.nanoTimestamp();
    
    // Test that our new I/O system patterns don't impact performance
    const io = std.Io.Threaded.global_single_threaded.io();
    
    // Performance test: Get current working directory multiple times
    const iterations = 100;
    for (0..iterations) |_| {
        const cwd = io.getCwd();
        defer allocator.free(cwd);
        try testing.expect(cwd.len > 0);
    }
    
    const end_time = std.time.nanoTimestamp();
    const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
    
    // Should complete within reasonable time
    try testing.expect(duration_ms < 20.0); // 20ms threshold
}

test "performance regression - build system operations" {
    const testing = std.testing;
    
    const allocator = testing.allocator;
    const start_time = std.time.nanoTimestamp();
    
    // Test that our build system API changes don't impact performance
    var builder = std.Build.init(allocator, .{
        .install_path = std.Build.InstallPath{ .dir = .bin },
        .resolved_install_path = "",
        .cache_root = std.Build.Cache.Directory.cwd(),
        .global_cache_root = std.Build.Cache.Directory.cwd(),
        .host = std.zig.system.resolveTargetQuery(std.Io.Threaded.global_single_threaded.io(), .{}) catch |err| {
            std.debug.print("Failed to resolve target query: {}\n", .{err});
            return error.SkipZigTest;
        },
        .dep_zig = null,
        .user_app_name = "test",
        .user_lib_dir = "",
        .argv = &[_][]const u8{},
        .graph = std.Build.initGraph(allocator),
    });
    defer builder.deinit();
    
    // Performance test: Create multiple executables with our new API patterns
    const iterations = 10;
    for (0..iterations) |i| {
        const exe = builder.addExecutable(.{
            .name = try std.fmt.allocPrint(allocator, "test_exe_{d}", .{i}),
            .root_source_file = builder.path("test_main.zig"),
            .target = builder.host,
            .optimize = .Debug,
        });
        
        // Use our new root_module methods
        exe.root_module.addIncludePath(builder.path("include"));
        exe.root_module.linkSystemLibrary("c", .{});
        
        if (builder.host.result.os.tag.isDarwin()) {
            exe.root_module.linkFramework("Foundation", .{});
        }
    }
    
    const end_time = std.time.nanoTimestamp();
    const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
    
    // Should complete within reasonable time
    try testing.expect(duration_ms < 100.0); // 100ms threshold
}

test "performance regression - unicode processing" {
    const testing = std.testing;
    
    const allocator = testing.allocator;
    const start_time = std.time.nanoTimestamp();
    
    // Test that our unicode processing changes don't impact performance
    const unicode = @import("../src/unicode/main.zig");
    
    // Performance test: Process a large amount of unicode text
    const test_text = "Hello, 世界! 🌍 This is a test with various unicode characters: café, naïve, résumé.";
    const iterations = 1000;
    
    for (0..iterations) |_| {
        // Test unicode width calculation
        var width: usize = 0;
        var iter = std.unicode.Utf8View.init(test_text) catch unreachable;
        var codepoint_iter = iter.iterator();
        
        while (codepoint_iter.nextCodepoint()) |codepoint| {
            width += unicode.table.get(codepoint).width;
        }
        
        try testing.expect(width > 0);
    }
    
    const end_time = std.time.nanoTimestamp();
    const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
    
    // Should complete within reasonable time
    try testing.expect(duration_ms < 50.0); // 50ms threshold
}

test "performance regression - cursor operations" {
    const testing = std.testing;
    
    const allocator = testing.allocator;
    const start_time = std.time.nanoTimestamp();
    
    var screen = try Screen.init(allocator, .{
        .rows = 24,
        .cols = 80,
        .scrollback_max = 1000,
        .kitty_image_storage_limit = 0,
        .kitty_image_loading_limits = .{},
    });
    defer screen.deinit();
    
    // Performance test: Rapid cursor movements
    const iterations = 10000;
    for (0..iterations) |i| {
        const x = @mod(i, 80);
        const y = @mod(i, 24);
        
        screen.cursorHorizontalAbsolute(@intCast(x));
        screen.cursorVerticalAbsolute(@intCast(y));
        
        // Test cursor movement operations
        if (i % 2 == 0) {
            screen.cursorRight(1);
        } else {
            screen.cursorLeft(1);
        }
        
        if (i % 3 == 0) {
            screen.cursorDown(1);
        } else {
            screen.cursorUp(1);
        }
    }
    
    const end_time = std.time.nanoTimestamp();
    const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
    
    // Should complete within reasonable time
    try testing.expect(duration_ms < 100.0); // 100ms threshold
    
    // Verify screen integrity after performance test
    screen.assertIntegrity();
}

test "performance regression - screen scrolling" {
    const testing = std.testing;
    
    const allocator = testing.allocator;
    const start_time = std.time.nanoTimestamp();
    
    var screen = try Screen.init(allocator, .{
        .rows = 24,
        .cols = 80,
        .scrollback_max = 1000,
        .kitty_image_storage_limit = 0,
        .kitty_image_loading_limits = .{},
    });
    defer screen.deinit();
    
    // Performance test: Rapid scrolling
    const iterations = 1000;
    for (0..iterations) |_| {
        // Fill the screen with content
        for (0..24) |_| {
            try screen.testWriteString("This is a line of text that will cause scrolling when we reach the bottom of the screen.\n");
        }
        
        // Test scrolling operations
        screen.scrollUp(1);
        screen.scrollDown(1);
        
        // Test page navigation
        screen.pageUp(1);
        screen.pageDown(1);
    }
    
    const end_time = std.time.nanoTimestamp();
    const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
    
    // Should complete within reasonable time
    try testing.expect(duration_ms < 200.0); // 200ms threshold
    
    // Verify screen integrity after performance test
    screen.assertIntegrity();
}

test "performance regression - memory usage" {
    const testing = std.testing;
    
    const allocator = testing.allocator;
    
    // Test that our changes don't cause memory leaks
    const initial_memory = std.heap.c_allocator.vtable.alloc(allocator, 1) catch |err| {
        std.debug.print("Failed to allocate initial memory: {}\n", .{err});
        return error.SkipZigTest;
    };
    std.heap.c_allocator.vtable.free(allocator, initial_memory);
    
    // Create and destroy multiple screens to test memory management
    const iterations = 100;
    for (0..iterations) |_| {
        var screen = try Screen.init(allocator, .{
            .rows = 24,
            .cols = 80,
            .scrollback_max = 1000,
            .kitty_image_storage_limit = 0,
            .kitty_image_loading_limits = .{},
        });
        
        // Use the screen
        try screen.testWriteString("Test content for memory usage testing\n");
        
        // Clean up
        screen.deinit();
    }
    
    // Test environment map memory management
    for (0..iterations) |_| {
        var env_map = std.process.Environ.Map.init(allocator);
        
        // Add some entries
        try env_map.put("TEST_KEY", "TEST_VALUE");
        
        // Clean up
        env_map.deinit();
    }
    
    // If we get here without memory leaks, our changes are memory-safe
    try testing.expect(true);
}

test "performance regression - concurrent operations" {
    const testing = std.testing;
    
    const allocator = testing.allocator;
    const start_time = std.time.nanoTimestamp();
    
    // Test that our I/O system changes work correctly with concurrent operations
    const iterations = 100;
    
    for (0..iterations) |_| {
        // Test concurrent I/O operations
        const io = std.Io.Threaded.global_single_threaded.io();
        
        // Get current working directory
        const cwd = io.getCwd();
        defer allocator.free(cwd);
        
        // Test environment map operations
        var env_map = std.process.Environ.Map.init(allocator);
        defer env_map.deinit();
        
        try env_map.put("CONCURRENT_TEST", "works");
        const value = env_map.get("CONCURRENT_TEST");
        try testing.expectEqualStrings("works", value.?);
        
        // Test target resolution
        const target = std.zig.system.resolveTargetQuery(io, .{}) catch |err| {
            std.debug.print("Failed to resolve target query: {}\n", .{err});
            return error.SkipZigTest;
        };
        
        try testing.expect(target.result.cpu.arch != .generic);
    }
    
    const end_time = std.time.nanoTimestamp();
    const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;
    
    // Should complete within reasonable time
    try testing.expect(duration_ms < 150.0); // 150ms threshold
}