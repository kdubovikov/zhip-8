const std = @import("std");
const rom = @import("rom.zig");
const dsp = @import("display.zig");

const memSize: usize = 4096; // 4 KB
const memStart: usize = 0x200; // 512, the first 512 bytes are reserved for the interpreter
const stackSize: usize = 16;

pub const Chip8Error = error{InvalidInstruction};

pub const Chip8 = struct {
    pc: u16, // program counter
    i: u16, // index register
    v: [16]u8, // general purpose registers
    stack: [16]u16, // stack,
    sp: u8, // stack pointer
    delayTimer: u8, // delay timer
    soundTimer: u8, // sound timer
    display: *dsp.Display,

    memory: [memSize]u8, // 4 KB

    const Self = @This();
    const VF = 15; // VF is used as a flag by some instructions

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
            .sp = 0,
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
    pub fn cycle(self: *Self) !void {
        const opcode = self.fetch();
        const instruction = try self.decode(opcode);
        try self.execute(instruction);
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
        // const nibble: u4 = @as(u4, @truncate(opcode >> 12));
        // _ = nibble;
        const secondNibble: u4 = @as(u4, @truncate((opcode >> 8) & 0x0F));
        const thirdNibble: u4 = @as(u4, @truncate((opcode >> 4) & 0x0F));
        const fourthNibble: u4 = @as(u4, @truncate(opcode & 0x0F));
        const lastByte: u8 = @as(u8, @truncate(opcode & 0xFF));
        const address: u12 = @as(u12, @truncate(opcode & 0x0FFF));

        const nibble = opcode & 0xF000;

        if (opcode == @intFromEnum(OpCodes.CLS)) {
            return Instruction{ .cls = .{ .opcode = opcode } };
        } else if (nibble == @intFromEnum(OpCodes.JMP)) {
            return Instruction{ .jmp = .{
                .opcode = opcode,
                .address = address,
            } };
        } else if (nibble == @intFromEnum(OpCodes.SETVX)) {
            return Instruction{ .setvx = .{
                .opcode = opcode,
                .register = secondNibble,
                .value = lastByte,
            } };
        } else if (nibble == @intFromEnum(OpCodes.ADDVX)) {
            return Instruction{ .addvx = .{
                .opcode = opcode,
                .register = secondNibble,
                .value = lastByte,
            } };
        } else if (nibble == @intFromEnum(OpCodes.SETI)) {
            return Instruction{ .seti = .{
                .opcode = opcode,
                .address = address,
            } };
        } else if (nibble == @intFromEnum(OpCodes.DRAW)) {
            return Instruction{ .draw = .{
                .opcode = opcode,
                .registerX = secondNibble,
                .registerY = thirdNibble,
                .height = fourthNibble,
            } };
        } else if (nibble == @intFromEnum(OpCodes.CALL)) {
            return Instruction{ .call = .{
                .opcode = opcode,
                .address = address,
            } };
        } else if (opcode == @intFromEnum(OpCodes.RET)) {
            return Instruction{ .ret = .{
                .opcode = opcode,
            } };
        } else if (nibble == @intFromEnum(OpCodes.SKIP_IF_EQUAL)) {
            return Instruction{ .skipIfEqual = .{
                .opcode = opcode,
                .register = secondNibble,
                .value = lastByte,
            } };
        } else if (nibble == @intFromEnum(OpCodes.SKIP_IF_NOT_EQUAL)) {
            return Instruction{ .skipIfNotEqual = .{
                .opcode = opcode,
                .register = secondNibble,
                .value = lastByte,
            } };
        } else if (nibble == @intFromEnum(OpCodes.SKIP_IF_EQUAL_REGISTER)) {
            return Instruction{ .skipIfEqualRegister = .{
                .opcode = opcode,
                .registerX = secondNibble,
                .registerY = thirdNibble,
            } };
        } else if (nibble == @intFromEnum(OpCodes.SKIP_IF_NOT_EQUAL_REGISTER)) {
            return Instruction{ .skipIfNotEqualRegister = .{
                .opcode = opcode,
                .registerX = secondNibble,
                .registerY = thirdNibble,
            } };
        } else if (nibble == 0x8000) { // arithmetic
            switch (fourthNibble) {
                @intFromEnum(OpCodes.REGISTER_SET) => {
                    return Instruction{ .registerSet = .{
                        .opcode = opcode,
                        .registerX = secondNibble,
                        .registerY = thirdNibble,
                    } };
                },
                @intFromEnum(OpCodes.AND) => {
                    return Instruction{ .binaryAnd = .{
                        .opcode = opcode,
                        .registerX = secondNibble,
                        .registerY = thirdNibble,
                    } };
                },
                @intFromEnum(OpCodes.OR) => {
                    return Instruction{ .binaryOr = .{
                        .opcode = opcode,
                        .registerX = secondNibble,
                        .registerY = thirdNibble,
                    } };
                },
                @intFromEnum(OpCodes.XOR) => {
                    return Instruction{ .binaryXor = .{
                        .opcode = opcode,
                        .registerX = secondNibble,
                        .registerY = thirdNibble,
                    } };
                },
                @intFromEnum(OpCodes.ADD_REGISTER_NO_CARRY) => {
                    return Instruction{ .addRegisterNoCarry = .{
                        .opcode = opcode,
                        .registerX = secondNibble,
                        .registerY = thirdNibble,
                    } };
                },
                @intFromEnum(OpCodes.SUBSTRACT_REGISTER_LR) => {
                    return Instruction{ .substractRegister = .{
                        .opcode = opcode,
                        .registerX = secondNibble,
                        .registerY = thirdNibble,
                    } };
                },
                @intFromEnum(OpCodes.SUBSTRACT_REGISTER_RL) => {
                    return Instruction{ .substractRegister = .{
                        .opcode = opcode,
                        .registerX = thirdNibble,
                        .registerY = secondNibble,
                    } };
                },
                @intFromEnum(OpCodes.SHIFT) => {
                    return Instruction{ .shift_right = .{
                        .opcode = opcode,
                        .registerX = secondNibble,
                        .registerY = thirdNibble,
                    } };
                },
                @intFromEnum(OpCodes.SHIFT_LEFT) => {
                    return Instruction{ .shift_left = .{
                        .opcode = opcode,
                        .registerX = secondNibble,
                        .registerY = thirdNibble,
                    } };
                },
                else => {
                    return Chip8Error.InvalidInstruction;
                },
            }
        } else {
            return Chip8Error.InvalidInstruction;
        }
    }

    // execute the instruction
    fn execute(self: *Self, instruction: Instruction) !void {
        switch (instruction) {
            .cls => {
                try self.display.clearScreen();
            },
            .jmp => |jmp_struct| {
                self.pc = jmp_struct.address;
            },
            .setvx => |setvx_struct| {
                self.v[setvx_struct.register] = setvx_struct.value;
            },
            .addvx => |addvx_struct| {
                self.v[addvx_struct.register] += addvx_struct.value;
            },
            .seti => |seti_struct| {
                self.i = seti_struct.address;
            },
            .draw => |draw_struct| {
                const x = self.v[draw_struct.registerX] & (dsp.displayWidth - 1);
                const y = self.v[draw_struct.registerY] & (dsp.displayHeight - 1);
                // std.debug.print("drawing sprite at x: {}, y: {}\n", .{ x, y });
                self.v[VF] = 0; // VF is set to 1 if any screen pixels are flipped from set to unset when the sprite is drawn, and to 0 if that doesn't happen

                for (0..draw_struct.height) |row| {
                    const sprite = self.memory[self.i + row];

                    for (0..8) |col| {
                        const colByte = @as(u3, @truncate(col));
                        const shiftBy: u8 = 0x80;
                        const pixel = sprite & @as(u8, (shiftBy >> colByte));
                        if (pixel != 0) {
                            const dspX = x + col;
                            const dspY = y + row;
                            const flipVF = try self.display.setPixel(dspX, dspY);
                            self.v[VF] = if (flipVF) 1 else 0;
                        }
                    }
                }
            },
            .call => |call_struct| {
                if (self.sp >= stackSize) {
                    std.debug.print("stack overflow\n", .{});
                    return error.InitError;
                }

                self.stack[self.sp] = self.pc;
                self.pc = call_struct.address;
                self.sp += 1;
            },
            .ret => |ret_struct| {
                _ = ret_struct;
                if (self.sp == 0) {
                    std.debug.print("stack underflow\n", .{});
                    return error.InitError;
                }

                self.pc = self.stack[self.sp];
                self.sp -= 1;
            },
            else => {
                std.debug.print("unimplemented instruction\n", .{});
            },
        }
    }
};

/// Combine two bytes into a single u16.
pub fn combine(a: u8, b: u8) u16 {
    return @as(u16, a) << 8 | @as(u16, b);
}

/// CHIP-8 instructions
const OpCodes = enum(u16) {
    CLS = 0x00E0, // Clear the display
    JMP = 0x1000, // Jump to address
    SETVX = 0x6000, // Set VX to NN
    ADDVX = 0x7000, // Add NN to VX
    SETI = 0xA000, // Set index register I to NNN
    DRAW = 0xD000, // Draw sprite at VX, VY with height N
    CALL = 0x2000, // Call subroutine at NNN
    RET = 0x00EE, // Return from subroutine
    SKIP_IF_EQUAL = 0x3000, // Skip next instruction if VX == NN
    SKIP_IF_NOT_EQUAL = 0x4000, // Skip next instruction if VX != NN
    SKIP_IF_EQUAL_REGISTER = 0x5000, // Skip next instruction if VX == VY
    SKIP_IF_NOT_EQUAL_REGISTER = 0x9000, // Skip next instruction if VX != VY

    // arithmetic operations 4th nibble mask
    REGISTER_SET = 0x0000, // Set VX to VY, or binary logic instructions
    AND = 0x0001, // Set VX to VX & VY
    OR = 0x0002, // Set VX to VX | VY
    XOR = 0x0003, // Set VX to VX ^ VY
    ADD_REGISTER_NO_CARRY = 0x0004, // Set VX to VX + VY, set VF to 1 if there is a carry, 0 otherwise
    SUBSTRACT_REGISTER_LR = 0x0005, // Set VX to VX - VY, set VF to 0 if there is a borrow, 1 otherwise
    SUBSTRACT_REGISTER_RL = 0x0007, // Set VX to VY - VX, set VF to 0 if there is a borrow, 1 otherwise
    SHIFT = 0x0006, // Set VX to VY >> 1, set VF to least significant bit of VY before shift
    SHIFT_LEFT = 0x000E, // Set VX to VY << 1, set VF to most significant bit of VY before shift
    // end arithmetic operations

    JUMP_WITH_OFFSET = 0xB000, // Jump to address NNN + V0
    RND = 0xC000, // Set VX to random number & NN
    SKIP_IF_KEY_PRESSED = 0xE09E, // Skip next instruction if key with value VX is pressed
    SKIP_IF_KEY_NOT_PRESSED = 0xE0A1, // Skip next instruction if key with value VX is not pressed
    GET_TIMER = 0xF007, // Set VX to value of delay timer
    SET_TIMER = 0xF015, // Set delay timer to VX
    SET_SOUND_TIMER = 0xF018, // Set sound timer to VX
    ADDI = 0xF01E, // Set I to I + VX
    GET_KEY = 0xF00A, // Wait for key press and store in VX
    FONT_CHARACTER = 0xF029, // Set I to location of sprite for character in VX
    DECIMAL = 0xF033, // Store BCD representation of VX in memory locations I, I+1, and I+2
    STORE_MEMORY = 0xF055, // Store registers V0 through VX in memory starting at location I
    LOAD_MEMORY = 0xF065, // Read registers V0 through VX from memory starting at location I
};

const Instruction = union(enum) {
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
    call: struct {
        opcode: u16,
        address: u12,
    },
    ret: struct {
        opcode: u16,
    },
    skipIfEqual: struct {
        opcode: u16,
        register: u4,
        value: u8,
    },
    skipIfNotEqual: struct {
        opcode: u16,
        register: u4,
        value: u8,
    },
    skipIfEqualRegister: struct {
        opcode: u16,
        registerX: u4,
        registerY: u4,
    },
    skipIfNotEqualRegister: struct {
        opcode: u16,
        registerX: u4,
        registerY: u4,
    },
    registerSet: struct {
        opcode: u16,
        registerX: u4,
        registerY: u4,
    },
    binaryOr: struct {
        opcode: u16,
        registerX: u4,
        registerY: u4,
    },
    binaryAnd: struct {
        opcode: u16,
        registerX: u4,
        registerY: u4,
    },
    binaryXor: struct {
        opcode: u16,
        registerX: u4,
        registerY: u4,
    },
    addRegisterNoCarry: struct {
        opcode: u16,
        registerX: u4,
        registerY: u4,
    },
    substractRegister: struct {
        opcode: u16,
        registerX: u4,
        registerY: u4,

        const Self = @This();
        pub fn xFirst(self: Self) bool {
            return self.opcode & 0x0005 == true;
        }
    },
    shift_right: struct {
        opcode: u16,
        registerX: u4,
        registerY: u4,
    },
    shift_left: struct {
        opcode: u16,
        registerX: u4,
        registerY: u4,
    },
    jumpWithOffset: struct {
        opcode: u16,
        register: u4,
    },
    random: struct {
        opcode: u16,
        register: u4,
        value: u8,
    },
    skipIfKeyPressed: struct {
        opcode: u16,
        register: u4,
    },
    getDelayTimer: struct {
        opcode: u16,
        register: u4,
    },
    setDelayTimer: struct {
        opcode: u16,
        register: u4,
    },
    setSoundTimer: struct {
        opcode: u16,
        register: u4,
    },
    addI: struct {
        opcode: u16,
        register: u4,
    },
    getKey: struct {
        opcode: u16,
        register: u4,
    },
    fontCharacter: struct {
        opcode: u16,
        register: u4,
    },
    binaryCodedDecimal: struct {
        opcode: u16,
        register: u4,
    },
    storeMemory: struct {
        opcode: u16,
        register: u4,
    },
    loadMemory: struct {
        opcode: u16,
        register: u4,
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

test "Decode CALL" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init("roms/IBM Logo.ch8", &display);

    var opcode: u16 = 0x2ABC;
    var i = try c.decode(opcode);
    try std.testing.expect(i.call.opcode == opcode);
    try std.testing.expect(i.call.address == 0xABC);
}

test "Decode RET" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init("roms/IBM Logo.ch8", &display);

    var opcode: u16 = 0x00EE;
    var i = try c.decode(opcode);
    try std.testing.expect(i.ret.opcode == opcode);
}

test "Decode SKIP_IF_EQUAL" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init("roms/IBM Logo.ch8", &display);

    var opcode: u16 = 0x3ABC;
    var i = try c.decode(opcode);
    try std.testing.expect(i.skipIfEqual.opcode == opcode);
    try std.testing.expect(i.skipIfEqual.register == 0xA);
    try std.testing.expect(i.skipIfEqual.value == 0xBC);
}

test "Decode SKIP_IF_NOT_EQUAL" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init("roms/IBM Logo.ch8", &display);

    var opcode: u16 = 0x4ABC;
    var i = try c.decode(opcode);
    try std.testing.expect(i.skipIfNotEqual.opcode == opcode);
    try std.testing.expect(i.skipIfNotEqual.register == 0xA);
    try std.testing.expect(i.skipIfNotEqual.value == 0xBC);
}

test "Decode SKIP_IF_EQUAL_REGISTER" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init("roms/IBM Logo.ch8", &display);

    var opcode: u16 = 0x5AB0;
    var i = try c.decode(opcode);
    try std.testing.expect(i.skipIfEqualRegister.opcode == opcode);
    try std.testing.expect(i.skipIfEqualRegister.registerX == 0xA);
    try std.testing.expect(i.skipIfEqualRegister.registerY == 0xB);
}

test "Decode SKIP_IF_NOT_EQUAL_REGISTER" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init("roms/IBM Logo.ch8", &display);

    var opcode: u16 = 0x9AB0;
    var i = try c.decode(opcode);
    try std.testing.expect(i.skipIfNotEqualRegister.opcode == opcode);
    try std.testing.expect(i.skipIfNotEqualRegister.registerX == 0xA);
    try std.testing.expect(i.skipIfNotEqualRegister.registerY == 0xB);
}

test "Decode REGISTER_SET" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init("roms/IBM Logo.ch8", &display);

    var opcode: u16 = 0x8AB0;
    var i = try c.decode(opcode);
    try std.testing.expect(i.registerSet.opcode == opcode);
    try std.testing.expect(i.registerSet.registerX == 0xA);
    try std.testing.expect(i.registerSet.registerY == 0xB);
}

test "Decode AND" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init("roms/IBM Logo.ch8", &display);

    // 0x8AB1
    var opcode: u16 = 0x8AB1;
    var i = try c.decode(opcode);
    try std.testing.expect(i.binaryAnd.opcode == opcode);
    try std.testing.expect(i.binaryAnd.registerX == 0xA);
    try std.testing.expect(i.binaryAnd.registerY == 0xB);
}

test "Decode OR" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init("roms/IBM Logo.ch8", &display);

    // 0x8AB2
    var opcode: u16 = 0x8AB2;
    var i = try c.decode(opcode);
    try std.testing.expect(i.binaryOr.opcode == opcode);
    try std.testing.expect(i.binaryOr.registerX == 0xA);
    try std.testing.expect(i.binaryOr.registerY == 0xB);
}

test "Decode XOR" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init("roms/IBM Logo.ch8", &display);

    // 0x8AB3
    var opcode: u16 = 0x8AB3;
    var i = try c.decode(opcode);
    try std.testing.expect(i.binaryXor.opcode == opcode);
    try std.testing.expect(i.binaryXor.registerX == 0xA);
    try std.testing.expect(i.binaryXor.registerY == 0xB);
}

test "Decode ADD_REGISTER_NO_CARRY" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init("roms/IBM Logo.ch8", &display);
    // 0x8AB4
    var opcode: u16 = 0x8AB4;
    var i = try c.decode(opcode);
    try std.testing.expect(i.addRegisterNoCarry.opcode == opcode);
    try std.testing.expect(i.addRegisterNoCarry.registerX == 0xA);
    try std.testing.expect(i.addRegisterNoCarry.registerY == 0xB);
}

test "Decode SUBSTRACT_REGISTER_LR" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init("roms/IBM Logo.ch8", &display);
    // 0x8AB5
    var opcode: u16 = 0x8AB5;
    var i = try c.decode(opcode);
    try std.testing.expect(i.substractRegister.opcode == opcode);
    try std.testing.expect(i.substractRegister.registerX == 0xA);
    try std.testing.expect(i.substractRegister.registerY == 0xB);
}

test "Decode SUBSTRACT_REGISTER_RL" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init("roms/IBM Logo.ch8", &display);
    // 0x8BA5
    var opcode: u16 = 0x8BA5;
    var i = try c.decode(opcode);
    try std.testing.expect(i.substractRegister.opcode == opcode);
    try std.testing.expect(i.substractRegister.registerX == 0xB);
    try std.testing.expect(i.substractRegister.registerY == 0xA);
}

test "Decode SHIFT" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init("roms/IBM Logo.ch8", &display);
    // 0x8AB6
    var opcode: u16 = 0x8AB6;
    var i = try c.decode(opcode);
    try std.testing.expect(i.shift_right.opcode == opcode);
    try std.testing.expect(i.shift_right.registerX == 0xA);
    try std.testing.expect(i.shift_right.registerY == 0xB);
}

test "Decode SHIFT_LEFT" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init("roms/IBM Logo.ch8", &display);
    // 0x8ABE
    var opcode: u16 = 0x8ABE;
    var i = try c.decode(opcode);
    try std.testing.expect(i.shift_left.opcode == opcode);
    try std.testing.expect(i.shift_left.registerX == 0xA);
    try std.testing.expect(i.shift_left.registerY == 0xB);
}

test "Execute CLS" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init("roms/IBM Logo.ch8", &display);
    var opcode: u16 = 0x00E0;
    var i = try c.decode(opcode);
    try c.execute(i);
    for (display.pixels[0..]) |*pixel| {
        try std.testing.expect(pixel.* == 0);
    }
}

test "Execute JMP" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init("roms/IBM Logo.ch8", &display);
    var opcode: u16 = 0x1ABC;
    var i = try c.decode(opcode);
    try c.execute(i);
    try std.testing.expect(c.pc == 0xABC);
}

test "Execute SETVX" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init("roms/IBM Logo.ch8", &display);
    var opcode: u16 = 0x6ABC;
    var i = try c.decode(opcode);
    try c.execute(i);
    try std.testing.expect(c.v[0xA] == 0xBC);
}

test "Execute ADDVX" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init("roms/IBM Logo.ch8", &display);
    c.v[0xA] = 0x01;
    var opcode: u16 = 0x7ABC;
    var i = try c.decode(opcode);
    try c.execute(i);
    try std.testing.expect(c.v[0xA] == 0xBC + 0x01);
}

test "Execute SETI" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init("roms/IBM Logo.ch8", &display);
    var opcode: u16 = 0xAABC;
    var i = try c.decode(opcode);
    try c.execute(i);
    try std.testing.expect(c.i == 0xABC);
}

test "Execute DRAW" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init("roms/IBM Logo.ch8", &display);

    // set up the display
    for (display.pixels[0..]) |*pixel| {
        pixel.* = 0;
    }

    // set up the memory
    c.i = 0x200;
    c.memory[c.i] = 0b10000000;

    var opcode: u16 = 0xD001;
    var i = try c.decode(opcode);
    try c.execute(i);

    // check the display
    try std.testing.expect(display.pixels[0] == 0xFFFFFFFF);
    try std.testing.expect(display.pixels[1] == 0);
    try std.testing.expect(display.pixels[2] == 0);
}

test "Execute CALL" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init("roms/IBM Logo.ch8", &display);

    var opcode: u16 = 0x2ABC;
    var i = try c.decode(opcode);
    try c.execute(i);
    try std.testing.expect(c.pc == 0xABC);
    try std.testing.expect(c.stack[0] == 0x200);
}
