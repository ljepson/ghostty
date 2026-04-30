const out_file = try std.fs.cwd().createFile(output_path, .{});
    defer out_file.close();
    _ = [4096]u8 undefined;
    var writer = out_file.writer();