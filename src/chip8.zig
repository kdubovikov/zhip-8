const std = @import("std");
const rom = @import("rom.zig");
const dsp = @import("display.zig");

const memSize: usize = 4096; // 4 KB
const memStart: usize = 0x200; // 512, the first 512 bytes are reserved for the interpreter

pub const Chip8Error = error{InvalidInstruction};

pub const Chip8 = struct {
    pc: u16, // program counter
    i: u16, // index register
    v: [16]u8, // general purpose registers
    stack: [16]u16, // stack,
    delayTimer: u8, // delay timer
    soundTimer: u8, // sound timer
    display: *dsp.Display,

    memory: [memSize]u8, // 4 KB

    const Self = @This();

    pub fn init(romPath: []const u8, display: *dsp.Display) !Self {
        var mem: [memSize]u8 = undefined;
        // clear memory
        for (mem[0..]) |*byte| {
            byte.* = 0;
        }

        var v = [_]u8{0} ** 16;
        var stack = [_]u16{0} ** 16;

        var ret = Self{
            .pc = memStart,
            .memory = mem,
            .i = 0,
            .v = v,
            .stack = stack,
            .delayTimer = 0,
            .soundTimer = 0,
            .display = display,
        };

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
        const opcode = combine(self.memory[self.pc], self.memory[self.pc + 1]);
        self.pc += 2;
        return opcode;
    }

    // decode the instruction
    fn decode(self: *Self, opcode: u16) !Instruction {
        _ = self;
        const nibble: u4 = @as(u4, @truncate(opcode >> 12));
        const secondNibble: u4 = @as(u4, @truncate((opcode >> 8) & 0x0F));
        const thirdNibble: u4 = @as(u4, @truncate((opcode >> 4) & 0x0F));
        const fourthNibble: u4 = @as(u4, @truncate(opcode & 0x0F));
        const lastByte: u8 = @as(u8, @truncate(opcode & 0xFF));
        const address: u12 = @as(u12, @truncate(opcode & 0x0FFF));

        switch (nibble) {
            @intFromEnum(OpCodes.CLS) => {
                return Instruction{ .cls = .{ .opcode = opcode } };
            },
            @intFromEnum(OpCodes.JMP) => {
                return Instruction{ .jmp = .{
                    .opcode = opcode,
                    .address = address,
                } };
            },
            @intFromEnum(OpCodes.SETVX) => {
                return Instruction{ .setvx = .{
                    .opcode = opcode,
                    .register = secondNibble,
                    .value = lastByte,
                } };
            },
            @intFromEnum(OpCodes.ADDVX) => {
                return Instruction{ .addvx = .{
                    .opcode = opcode,
                    .register = secondNibble,
                    .value = lastByte,
                } };
            },
            @intFromEnum(OpCodes.SETI) => {
                return Instruction{ .seti = .{
                    .opcode = opcode,
                    .address = address,
                } };
            },
            @intFromEnum(OpCodes.DRAW) => {
                return Instruction{ .draw = .{
                    .opcode = opcode,
                    .registerX = secondNibble,
                    .registerY = thirdNibble,
                    .height = fourthNibble,
                } };
            },
            else => {
                return Chip8Error.InvalidInstruction;
            },
        }
    }

    // execute the instruction
    fn execute(self: *Self) void {
        _ = self;
    }
};

/// Combine two bytes into a single u16.
pub fn combine(a: u8, b: u8) u16 {
    return @as(u16, a) << 8 | @as(u16, b);
}

/// CHIP-8 instructions
const OpCodes = enum(u4) {
    CLS = 0x0, // Clear the display
    JMP = 0x1, // Jump to address
    SETVX = 0x6, // Set VX to NN
    ADDVX = 0x7, // Add NN to VX
    SETI = 0xA, // Set index register I to NNN
    DRAW = 0xD, // Draw sprite at VX, VY with height N
};

const Instruction = union {
    cls: struct {
        opcode: u16,
    },
    jmp: struct {
        opcode: u16,
        address: u12,
    },
    setvx: struct {
        opcode: u16,
        register: u4,
        value: u8,
    },
    addvx: struct {
        opcode: u16,
        register: u4,
        value: u8,
    },
    seti: struct {
        opcode: u16,
        address: u12,
    },
    draw: struct {
        opcode: u16,
        registerX: u4,
        registerY: u4,
        height: u4,
    },
};

test "nibble check" {
    var a: u16 = 0x1234;
    var mask1: u16 = 0x1200;
    try std.testing.expectEqual((a & mask1), 0x1200);
}

test "combine bytes" {
    var a: u8 = 0x12;
    var b: u8 = 0x34;
    var c = combine(a, b);
    try std.testing.expect(c == 0x1234);
}

test "Load ROM and check memory contents" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init("roms/IBM Logo.ch8", &display);
    var r = try rom.Rom.load("roms/IBM Logo.ch8");
    for (r.data[0..]) |*byte| {
        try std.testing.expect(byte.* == c.memory[c.pc]);
        c.pc += 1;
    }
}

test "Decode CLS" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init("roms/IBM Logo.ch8", &display);
    var opcode: u16 = 0x00E0;
    var i = try c.decode(opcode);
    try std.testing.expect(i.cls.opcode == opcode);
}

test "Decode JMP" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init("roms/IBM Logo.ch8", &display);
    var opcode: u16 = 0x1ABC;
    var i = try c.decode(opcode);
    try std.testing.expect(i.jmp.opcode == opcode);
    try std.testing.expect(i.jmp.address == 0xABC);
}

test "Decode SETVX" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init("roms/IBM Logo.ch8", &display);
    var opcode: u16 = 0x6ABC;
    var i = try c.decode(opcode);
    try std.testing.expect(i.setvx.opcode == opcode);
    try std.testing.expect(i.setvx.register == 0xA);
    try std.testing.expect(i.setvx.value == 0xBC);
}

test "Decode ADDVX" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init("roms/IBM Logo.ch8", &display);
    var opcode: u16 = 0x7ABC;
    var i = try c.decode(opcode);
    try std.testing.expect(i.addvx.opcode == opcode);
    try std.testing.expect(i.addvx.register == 0xA);
    try std.testing.expect(i.addvx.value == 0xBC);
}

test "Decode SETI" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init("roms/IBM Logo.ch8", &display);
    var opcode: u16 = 0xAABC;
    var i = try c.decode(opcode);
    try std.testing.expect(i.seti.opcode == opcode);
    try std.testing.expect(i.seti.address == 0xABC);
}

test "Decode DRAW" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init("roms/IBM Logo.ch8", &display);
    var opcode: u16 = 0xDABC;
    var i = try c.decode(opcode);
    try std.testing.expect(i.draw.opcode == opcode);
    try std.testing.expect(i.draw.registerX == 0xA);
    try std.testing.expect(i.draw.registerY == 0xB);
    try std.testing.expect(i.draw.height == 0xC);
}
