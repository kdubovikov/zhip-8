const std = @import("std");

pub const Rom = struct {
    size: usize,
    data: []u8,

    const Self = @This();

    pub fn load(path: []const u8) !Self {
        var file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        var size = (try file.stat()).size;
        var allocator = std.heap.page_allocator;

        var data = try allocator.alloc(u8, size);
        _ = try file.readAll(data);
        return Self{ .size = size, .data = data[0..] };
    }
};

test "load rom" {
    var rom = try Rom.load("roms/IBM Logo.ch8");
    _ = rom;
}
