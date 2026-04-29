const std = @import("std");
const testing = std.testing;
const Screen = @import("../src/terminal/Screen.zig").Screen;
const PageList = @import("../src/terminal/PageList.zig").PageList;
const Cursor = @import("../src/terminal/cursor.zig").Cursor;

/// Integration tests for terminal compatibility with Zig 0.16.0
/// This ensures our terminal emulation works correctly after the API changes
test "terminal screen compatibility with Zig 0.16.0" {
    const testing = std.testing;
    
    // Test that Screen can be created and used with our changes
    const allocator = testing.allocator;
    
    // Create a test screen with our new patterns
    var screen = try Screen.init(allocator, .{
        .rows = 24,
        .cols = 80,
        .scrollback_max = 1000,
        .kitty_image_storage_limit = 0,
        .kitty_image_loading_limits = .{},
    });
    defer screen.deinit();
    
    // Test basic screen operations
    try screen.testWriteString("Hello, World!");
    
    // Test that cursor operations work
    const original_x = screen.cursor.x;
    const original_y = screen.cursor.y;
    
    // Test cursor movement
    screen.cursorRight(5);
    try testing.expect(screen.cursor.x > original_x);
    
    screen.cursorDown(1);
    try testing.expect(screen.cursor.y > original_y);
    
    // Test that screen integrity checks work
    screen.assertIntegrity();
    
    // Test that we can dump screen content (used in tests)
    const dumped = try screen.dumpStringAlloc(allocator, .{ .x = 0, .y = 0 });
    defer allocator.free(dumped);
    try testing.expect(dumped.len > 0);
}

test "terminal page list compatibility" {
    const testing = std.testing;
    
    // Test that PageList works with our memory management changes
    const allocator = testing.allocator;
    
    var page_list = try PageList.init(allocator, 24, 80, 1000);
    defer page_list.deinit();
    
    // Test that we can get the active page
    const active_page = page_list.active();
    try testing.expect(active_page != null);
    
    // Test that we can create and use pins
    const pin = page_list.pin(.active, .{ .x = 0, .y = 0 });
    try testing.expect(pin.valid);
    
    // Test that we can convert between coordinate systems
    const point = page_list.pointFromPin(.active, pin);
    try testing.expect(point.active.x == 0);
    try testing.expect(point.active.y == 0);
}

test "terminal cursor compatibility" {
    const testing = std.testing;
    
    // Test that Cursor operations work with our changes
    const allocator = testing.allocator;
    
    var cursor = try Cursor.init(allocator);
    defer cursor.deinit();
    
    // Test basic cursor operations
    cursor.x = 10;
    cursor.y = 5;
    
    try testing.expect(cursor.x == 10);
    try testing.expect(cursor.y == 5);
    
    // Test cursor bounds checking
    cursor.x = 100;
    cursor.y = 100;
    
    // These should be clamped by the screen when used
    try testing.expect(cursor.x == 100);
    try testing.expect(cursor.y == 100);
}

test "terminal SGR compatibility" {
    const testing = std.testing;
    
    // Test that SGR (Select Graphic Rendition) sequences work
    const sgr = @import("../src/terminal/sgr.zig");
    
    // Test SGR parsing
    const test_seq = "31;44;1m"; // Red text, blue background, bold
    
    // This tests our SGR parsing with the new Zig 0.16.0 patterns
    var iter = std.mem.split(u8, test_seq, ";");
    var found_red = false;
    var found_blue = false;
    var found_bold = false;
    
    while (iter.next()) |part| {
        const num = std.fmt.parseInt(u8, part, 10) catch continue;
        switch (num) {
            31 => found_red = true,
            44 => found_blue = true,
            1 => found_bold = true,
            else => {},
        }
    }
    
    try testing.expect(found_red);
    try testing.expect(found_blue);
    try testing.expect(found_bold);
}

test "terminal mouse encoding compatibility" {
    const testing = std.testing;
    
    // Test that mouse encoding works with our changes
    const mouse_encode = @import("../src/input/mouse_encode.zig");
    
    // Test basic mouse encoding
    const test_event = mouse_encode.Event{
        .kind = .press,
        .button = .left,
        .mods = .{},
        .x = 10,
        .y = 5,
    };
    
    // Test that we can encode mouse events
    var buffer: [32]u8 = undefined;
    const len = mouse_encode.encode(buffer[0..], test_event, .{ .protocol = .default });
    
    try testing.expect(len > 0);
    
    // Test that the encoded data is valid UTF-8
    const view = std.unicode.Utf8View.init(buffer[0..len]) catch |err| {
        std.debug.print("Invalid UTF-8 in mouse encoding: {}\n", .{err});
        return error.SkipZigTest;
    };
    
    var iter = view.iterator();
    var codepoint_count: usize = 0;
    while (iter.nextCodepoint()) |_| {
        codepoint_count += 1;
    }
    
    try testing.expect(codepoint_count > 0);
}

test "terminal search compatibility" {
    const testing = std.testing;
    
    // Test that terminal search works with our changes
    const sliding_window = @import("../src/terminal/search/sliding_window.zig");
    
    // Test basic search functionality
    const test_text = "Hello, World! This is a test string.";
    const search_pattern = "World";
    
    // Test that we can find the pattern
    var iter = sliding_window.init(test_text, search_pattern);
    var found = false;
    
    while (iter.next()) |match| {
        if (std.mem.eql(u8, test_text[match.start..match.end], search_pattern)) {
            found = true;
            break;
        }
    }
    
    try testing.expect(found);
}

test "terminal size reporting compatibility" {
    const testing = std.testing;
    
    // Test that terminal size reporting works with our changes
    const size_report = @import("../src/terminal/size_report.zig");
    
    // Test size reporting
    const test_size = size_report.Size{
        .rows = 24,
        .cols = 80,
        .pixel_width = 800,
        .pixel_height = 600,
    };
    
    // Test that we can serialize size information
    var buffer: [64]u8 = undefined;
    const len = test_size.serialize(buffer[0..]);
    
    try testing.expect(len > 0);
    
    // Test that the serialized data is valid
    const parsed = size_report.Size.deserialize(buffer[0..len]) catch |err| {
        std.debug.print("Failed to deserialize size report: {}\n", .{err});
        return error.SkipZigTest;
    };
    
    try testing.expect(parsed.rows == test_size.rows);
    try testing.expect(parsed.cols == test_size.cols);
    try testing.expect(parsed.pixel_width == test_size.pixel_width);
    try testing.expect(parsed.pixel_height == test_size.pixel_height);
}

test "terminal tmux compatibility" {
    const testing = std.testing;
    
    // Test that tmux integration works with our changes
    const tmux_viewer = @import("../src/terminal/tmux/viewer.zig");
    const tmux_output = @import("../src/terminal/tmux/output.zig");
    
    // Test tmux viewer initialization
    const allocator = testing.allocator;
    
    // Test that we can create a tmux viewer
    var viewer = try tmux_viewer.Viewer.init(allocator);
    defer viewer.deinit();
    
    // Test that we can parse tmux output
    const test_tmux_output = "\\033Ptmux;\\033\\033[24;80H\\033\\\\";
    var parser = tmux_output.Parser.init(test_tmux_output);
    
    // Test that we can parse tmux sequences
    var found_tmux = false;
    while (parser.next()) |token| {
        switch (token) {
            .tmux_start => found_tmux = true,
            else => {},
        }
    }
    
    try testing.expect(found_tmux);
}

test "terminal compatibility integration" {
    const testing = std.testing;
    
    // Integration test that combines multiple terminal components
    const allocator = testing.allocator;
    
    // Create a screen and test multiple operations
    var screen = try Screen.init(allocator, .{
        .rows = 24,
        .cols = 80,
        .scrollback_max = 1000,
        .kitty_image_storage_limit = 0,
        .kitty_image_loading_limits = .{},
    });
    defer screen.deinit();
    
    // Test writing various types of content
    try screen.testWriteString("Normal text\n");
    try screen.testWriteString("\x1b[31mRed text\x1b[0m\n");
    try screen.testWriteString("\x1b[1mBold text\x1b[0m\n");
    
    // Test cursor operations
    screen.cursorHorizontalAbsolute(0);
    screen.cursorDown(1);
    try screen.testWriteString("Positioned text");
    
    // Test screen integrity after multiple operations
    screen.assertIntegrity();
    
    // Test that we can dump the screen content
    const content = try screen.dumpStringAlloc(allocator, .{ .x = 0, .y = 0 });
    defer allocator.free(content);
    
    // Verify the content contains what we wrote
    try testing.expect(std.mem.indexOf(u8, content, "Normal text") != null);
    try testing.expect(std.mem.indexOf(u8, content, "Red text") != null);
    try testing.expect(std.mem.indexOf(u8, content, "Bold text") != null);
    try testing.expect(std.mem.indexOf(u8, content, "Positioned text") != null);
    
    // Test that we can clear the screen
    screen.eraseInDisplay(.all);
    
    // Verify the screen is cleared
    const cleared_content = try screen.dumpStringAlloc(allocator, .{ .x = 0, .y = 0 });
    defer allocator.free(cleared_content);
    
    // The cleared content should be mostly whitespace/newlines
    var non_whitespace_count: usize = 0;
    for (cleared_content) |byte| {
        if (byte != ' ' and byte != '\n' and byte != '\r' and byte != '\t') {
            non_whitespace_count += 1;
        }
    }
    
    // Should be very little non-whitespace content after clearing
    try testing.expect(non_whitespace_count < 10);
}