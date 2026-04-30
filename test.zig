const std = @import("std"); 
pub fn main() !void { 
    const file = try std.fs.cwd().openFile("test.txt", .{}); 
    defer file.close();
    std.debug.print("success\n"); 
}
