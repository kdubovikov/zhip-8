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

    /// Read a single instruction from the ROM.
    /// Returns 0 if the instruction is out of bounds.
    pub fn readInstruction(self: Self, offset: usize) u16 {
        if (offset + 2 > self.size) {
            return 0;
        }

        var data = self.data[offset..];
        return combine(data[0], data[1]);
    }
};

/// Combine two bytes into a single u16.
fn combine(a: u8, b: u8) u16 {
    return @as(u16, a) << 8 | @as(u16, b);
}

test "combine bytes" {
    var a: u8 = 0x12;
    var b: u8 = 0x34;
    var c = combine(a, b);
    try std.testing.expect(c == 0x1234);
}

test "load rom" {
    var rom = try Rom.load("roms/IBM Logo.ch8");
    const inst = rom.readInstruction(0);
    try std.testing.expect(inst == 0x00e0);
}
