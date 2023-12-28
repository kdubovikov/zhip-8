const std = @import("std");
const rom = @import("rom.zig");

const memSize: usize = 4096; // 4 KB
const memStart: usize = 0x200; // 512, the first 512 bytes are reserved for the interpreter

pub const Chip8 = struct {
    pc: u16,
    memory: [memSize]u8, // 4 KB

    const Self = @This();

    pub fn init(romPath: []const u8) !Self {
        var mem: [memSize]u8 = undefined;
        // clear memory
        for (mem[0..]) |*byte| {
            byte.* = 0;
        }

        var ret = Self{ .pc = memStart, .memory = mem };

        // load rom
        var r = try rom.Rom.load(romPath);
        ret.loadRom(r);
        return ret;
    }

    /// Load a ROM into memory
    pub fn loadRom(self: *Self, r: rom.Rom) void {
        var pc = memStart;
        for (r.data[0..]) |*byte| {
            self.memory[pc] = byte.*;
            pc += 1;
        }
    }

    // cycle through the fetch, decode, and execute steps
    pub fn cycle(self: *Self) void {
        const opcode = self.fetch();
        self.decode(opcode);
        self.execute();
    }

    // fetch the next instruction and increment the program counter
    fn fetch(self: *Self) u16 {
        _ = self;
    }

    // decode the instruction
    fn decode(self: *Self, opcode: u16) void {
        _ = self;
        _ = opcode;
    }

    // execute the instruction
    fn execute(self: *Self) void {
        _ = self;
    }
};

test "Load ROM and check memory contents" {
    var c = try Chip8.init("roms/IBM Logo.ch8");
    var r = try rom.Rom.load("roms/IBM Logo.ch8");
    for (r.data[0..]) |*byte| {
        try std.testing.expect(byte.* == c.memory[c.pc]);
        c.pc += 1;
    }
}
