const std = @import("std"); pub fn main() !void { const file = try std.fs.File.openFile("test.txt", .{}); _ = file; std.debug.print("success\n"); }
