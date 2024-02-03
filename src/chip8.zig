const std = @import("std");
const rom = @import("rom.zig");
const dsp = @import("display.zig");
const font = @import("font.zig");

const memSize: usize = 4096; // 4 KB
const memStart: usize = 0x200; // 512, the first 512 bytes are reserved for the interpreter
const stackSize: usize = 16;
const fontOffset: usize = 0x0;
const timerFrequency: u64 = (1 / 60 * 1000); // 60 Hz

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
    timestamp: i64,

    memory: [memSize]u8, // 4 KB

    const Self = @This();
    const VF = 15; // VF is used as a flag by some instructions

    pub fn init(display: *dsp.Display) !Self {
        var mem: [memSize]u8 = undefined;
        // clear memory
        for (mem[0..]) |*byte| {
            byte.* = 0;
        }

        var v = [_]u8{0} ** 16;
        var stack = [_]u16{0} ** 16;

        // load font into interpreter-reserved memory
        for (0.., font.font) |i, byte| {
            mem[fontOffset + i] = byte;
        }

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
            .timestamp = std.time.microTimestamp(),
        };

        return ret;
    }

    pub fn initWithRom(romPath: []const u8, display: *dsp.Display) !Self {
        var ret = try Self.init(display);
        // load rom
        var r = try rom.Rom.load(romPath);
        ret.loadRom(r);
        return ret;
    }

    /// Load a ROM into memory
    pub fn loadRom(self: *Self, r: rom.Rom) void {
        self.loadFromBytes(r.data);
    }

    pub fn loadFromArray(self: *Self, bytes: []const u16) void {
        var pc = memStart;
        for (bytes[0..]) |*byte| {
            // load next 2 instructions from byte to memory and increment pc
            self.memory[pc] = @as(u8, @truncate(byte.* >> 8));
            self.memory[pc + 1] = @as(u8, @truncate(byte.* & 0xFF));
            pc += 2;
        }
    }

    pub fn loadFromBytes(self: *Self, bytes: []const u8) void {
        var pc = memStart;
        for (bytes[0..]) |*byte| {
            self.memory[pc] = byte.*;
            pc += 1;
        }
    }

    pub fn updateTimers(self: *Self, timestamp: i64) void {
        if (timestamp - self.timestamp >= timerFrequency) {
            if (self.delayTimer > 0) {
                self.delayTimer -= 1;
            }

            if (self.soundTimer > 0) {
                self.soundTimer -= 1;
            }

            self.timestamp = timestamp;
        }
    }

    // cycle through the fetch, decode, and execute steps
    pub fn cycle(self: *Self) !void {
        const opcode = self.fetch();
        const instruction = try self.decode(opcode);
        try self.execute(instruction);
        self.updateTimers(std.time.milliTimestamp());
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
        } else if (nibble == @intFromEnum(OpCodes.JUMP_WITH_OFFSET)) {
            return Instruction{ .jumpWithOffset = .{
                .opcode = opcode,
                .address = address,
            } };
        } else if (nibble == @intFromEnum(OpCodes.SKIP_KEY_NIBBLE)) {
            // skip key instructions decoding
            if (lastByte == @intFromEnum(OpCodes.SKIP_IF_KEY_PRESSED)) {
                return Instruction{ .skipIfKeyPressed = .{
                    .opcode = opcode,
                    .register = secondNibble,
                } };
            } else if (lastByte == @intFromEnum(OpCodes.SKIP_IF_KEY_NOT_PRESSED)) {
                return Instruction{ .skipIfKeyNotPressed = .{
                    .opcode = opcode,
                    .register = secondNibble,
                } };
            } else {
                std.log.err("Invalid instruction 0x{x}\n", .{opcode});
                return Chip8Error.InvalidInstruction;
            }
        } else if (nibble == @intFromEnum(OpCodes.RND)) {
            return Instruction{ .random = .{
                .opcode = opcode,
                .register = secondNibble,
                .value = lastByte,
            } };
        } else if (nibble == @intFromEnum(OpCodes.MISC_NIBBLE)) {
            // I/O and timer instructions
            if (lastByte == 0x0007) {
                return Instruction{ .getDelayTimer = .{
                    .opcode = opcode,
                    .register = secondNibble,
                } };
            } else if (lastByte == @intFromEnum(OpCodes.SET_TIMER)) {
                return Instruction{ .setDelayTimer = .{
                    .opcode = opcode,
                    .register = secondNibble,
                } };
            } else if (lastByte == @intFromEnum(OpCodes.SET_SOUND_TIMER)) {
                return Instruction{ .setSoundTimer = .{
                    .opcode = opcode,
                    .register = secondNibble,
                } };
            } else if (lastByte == @intFromEnum(OpCodes.ADDI)) {
                return Instruction{ .addI = .{
                    .opcode = opcode,
                    .register = secondNibble,
                } };
            } else if (lastByte == @intFromEnum(OpCodes.GET_KEY)) {
                return Instruction{ .getKey = .{
                    .opcode = opcode,
                    .register = secondNibble,
                } };
            } else if (lastByte == @intFromEnum(OpCodes.FONT_CHARACTER)) {
                return Instruction{ .fontCharacter = .{
                    .opcode = opcode,
                    .register = secondNibble,
                } };
            } else if (lastByte == @intFromEnum(OpCodes.DECIMAL)) {
                return Instruction{ .binaryCodedDecimal = .{
                    .opcode = opcode,
                    .register = secondNibble,
                } };
            } else if (lastByte == @intFromEnum(OpCodes.STORE_MEMORY)) {
                return Instruction{ .storeMemory = .{
                    .opcode = opcode,
                    .register = secondNibble,
                } };
            } else if (lastByte == @intFromEnum(OpCodes.LOAD_MEMORY)) {
                return Instruction{ .loadMemory = .{
                    .opcode = opcode,
                    .register = secondNibble,
                } };
            } else {
                std.log.err("Invalid instruction 0x{x}\n", .{opcode});
                return Chip8Error.InvalidInstruction;
            }
        } else if (nibble == @intFromEnum(OpCodes.ARITHMETIC_NIBBLE)) { // arithmetic
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
                        .lr = true,
                        .registerX = secondNibble,
                        .registerY = thirdNibble,
                    } };
                },
                @intFromEnum(OpCodes.SUBSTRACT_REGISTER_RL) => {
                    return Instruction{ .substractRegister = .{
                        .opcode = opcode,
                        .lr = false,
                        .registerX = secondNibble,
                        .registerY = thirdNibble,
                    } };
                },
                @intFromEnum(OpCodes.SHIFT) => {
                    return Instruction{ .shiftRight = .{
                        .opcode = opcode,
                        .registerX = secondNibble,
                        .registerY = thirdNibble,
                    } };
                },
                @intFromEnum(OpCodes.SHIFT_LEFT) => {
                    return Instruction{ .shiftLeft = .{
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
                return;
            },
            .setvx => |setvx_struct| {
                self.v[setvx_struct.register] = setvx_struct.value;
            },
            .addvx => |addvx_struct| {
                const ov = @addWithOverflow(self.v[addvx_struct.register], addvx_struct.value);
                self.v[addvx_struct.register] = ov[0];
                if (ov[1] == 1) {
                    self.v[VF] = 1;
                } else {
                    self.v[VF] = 0;
                }
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

                self.memory[self.sp] = @as(u8, @truncate(self.pc & 0x00FF));
                self.memory[self.sp + 1] = @as(u8, @truncate((self.pc & 0xFF00) >> 8));
                self.sp += 2;
                self.pc = call_struct.address;
                return;
            },
            .ret => |ret_struct| {
                _ = ret_struct;
                if (self.sp == 0) {
                    std.debug.print("stack underflow\n", .{});
                    return error.InitError;
                }

                self.pc = combine(self.memory[self.sp - 1], self.memory[self.sp - 2]);
                self.sp -= 2;
                return;
            },
            .skipIfEqual => |skip_if_equal_struct| {
                if (self.v[skip_if_equal_struct.register] == skip_if_equal_struct.value) {
                    self.pc += 2;
                }
            },
            .skipIfNotEqual => |skip_if_not_equal_struct| {
                if (self.v[skip_if_not_equal_struct.register] != skip_if_not_equal_struct.value) {
                    self.pc += 2;
                }
            },
            .skipIfEqualRegister => |skip_if_equal_register_struct| {
                if (self.v[skip_if_equal_register_struct.registerX] == self.v[skip_if_equal_register_struct.registerY]) {
                    self.pc += 2;
                }
            },
            .skipIfNotEqualRegister => |skip_if_not_equal_register_struct| {
                if (self.v[skip_if_not_equal_register_struct.registerX] != self.v[skip_if_not_equal_register_struct.registerY]) {
                    self.pc += 2;
                }
            },
            .registerSet => |register_set_struct| {
                self.v[register_set_struct.registerX] = self.v[register_set_struct.registerY];
            },
            .binaryAnd => |binary_and_struct| {
                self.v[binary_and_struct.registerX] &= self.v[binary_and_struct.registerY];
            },
            .binaryOr => |binary_or_struct| {
                self.v[binary_or_struct.registerX] |= self.v[binary_or_struct.registerY];
            },
            .binaryXor => |binary_xor_struct| {
                self.v[binary_xor_struct.registerX] ^= self.v[binary_xor_struct.registerY];
            },
            .addRegisterNoCarry => |add_register_no_carry_struct| {
                const sum = @addWithOverflow(self.v[add_register_no_carry_struct.registerX], self.v[add_register_no_carry_struct.registerY]);
                self.v[add_register_no_carry_struct.registerX] = sum[0];
                self.v[VF] = sum[1];
            },
            .substractRegister => |substract_register_struct| {
                var x: u8 = 0;
                var y: u8 = 0;
                if (substract_register_struct.lr) {
                    x = self.v[substract_register_struct.registerX];
                    y = self.v[substract_register_struct.registerY];
                } else {
                    x = self.v[substract_register_struct.registerY];
                    y = self.v[substract_register_struct.registerX];
                }
                const sub = @subWithOverflow(x, y);
                self.v[substract_register_struct.registerX] = sub[0];
                self.v[VF] = 1 - sub[1];
            },
            .shiftRight => |shift_struct| {
                const tmp = self.v[shift_struct.registerX] & 0x1;
                // self.v[shift_struct.registerX] = self.v[shift_struct.registerY];
                self.v[shift_struct.registerX] = self.v[shift_struct.registerX] >> 1;
                self.v[VF] = tmp;
            },
            .shiftLeft => |shift_left_struct| {
                const tmp = self.v[shift_left_struct.registerX] >> 7;
                // self.v[shift_left_struct.registerX] = self.v[shift_left_struct.registerY];
                self.v[shift_left_struct.registerX] = self.v[shift_left_struct.registerX] << 1;
                self.v[VF] = tmp;
            },
            .jumpWithOffset => |jump_with_offset_struct| {
                self.pc = self.i + jump_with_offset_struct.address;
            },
            .random => |random_struct| {
                var rnd = std.rand.DefaultPrng.init(@intCast(std.time.milliTimestamp()));
                const random = rnd.random().uintAtMost(u8, 254) + 1;
                self.v[random_struct.register] = random & random_struct.value;
            },
            .skipIfKeyPressed => |skip_if_key_pressed_struct| {
                const key = self.v[skip_if_key_pressed_struct.register];
                if (self.display.keyPressed(key)) {
                    // std.debug.print("key p: {}\n", .{key});
                    self.pc += 2;
                }
            },
            .skipIfKeyNotPressed => |skip_if_key_not_pressed_struct| {
                const key = self.v[skip_if_key_not_pressed_struct.register];
                if (!self.display.keyPressed(key)) {
                    // std.debug.print("key notp: {}\n", .{key});
                    self.pc += 2;
                }
            },
            .getKey => |get_key_struct| {
                // std.debug.print("getkey", .{});
                const key = self.display.getPressedKey();
                if (key == 0xFF) {
                    // std.debug.print("getkey - none", .{});
                    self.pc -= 2;
                } else {
                    self.v[get_key_struct.register] = key;
                    // std.debug.print("getkey - {}", .{key});
                }
            },
            .getDelayTimer => |get_delay_timer_struct| {
                self.v[get_delay_timer_struct.register] = self.delayTimer;
            },
            .setDelayTimer => |set_delay_timer_struct| {
                self.delayTimer = self.v[set_delay_timer_struct.register];
            },
            .setSoundTimer => |set_sound_timer_struct| {
                self.soundTimer = self.v[set_sound_timer_struct.register];
            },
            .addI => |add_i_struct| {
                self.i += self.v[add_i_struct.register];
            },
            .fontCharacter => |font_character_struct| {
                const character = self.v[font_character_struct.register];
                const lastNibble = character & 0x0F;
                // each character is 5 bytes long
                self.i = lastNibble;
            },
            .binaryCodedDecimal => |bcd_struct| {
                const value = self.v[bcd_struct.register];
                self.memory[self.i] = value / 100;
                self.memory[self.i + 1] = (value / 10) % 10;
                self.memory[self.i + 2] = value % 10;
            },
            .storeMemory => |store_memory_struct| {
                const x = store_memory_struct.register;
                var i: u8 = 0;
                while (i <= x) {
                    self.memory[self.i + i] = self.v[i];
                    i += 1;
                }
            },
            .loadMemory => |load_memory_struct| {
                const x = load_memory_struct.register;
                // std.debug.print("loading memory up to {}\n", .{x});
                var i: u8 = 0;
                while (i <= x) {
                    // std.debug.print("{} loading memory at {} with {}\n", .{ i, self.i + i, self.memory[self.i + i] });
                    self.v[i] = self.memory[self.i + i];
                    i += 1;
                }
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
    ARITHMETIC_NIBBLE = 0x8000,
    REGISTER_SET = 0x0000, // Set VX to VY, or binary logic instructions
    OR = 0x0001, // Set VX to VX & VY
    AND = 0x0002, // Set VX to VX | VY
    XOR = 0x0003, // Set VX to VX ^ VY
    ADD_REGISTER_NO_CARRY = 0x0004, // Set VX to VX + VY, set VF to 1 if there is a carry, 0 otherwise
    SUBSTRACT_REGISTER_LR = 0x0005, // Set VX to VX - VY, set VF to 0 if there is a borrow, 1 otherwise
    SUBSTRACT_REGISTER_RL = 0x0007, // Set VX to VY - VX, set VF to 0 if there is a borrow, 1 otherwise
    SHIFT = 0x0006, // Set VX to VY >> 1, set VF to least significant bit of VY before shift
    SHIFT_LEFT = 0x000E, // Set VX to VY << 1, set VF to most significant bit of VY before shift
    // end arithmetic operations

    JUMP_WITH_OFFSET = 0xB000, // Jump to address NNN + V0
    RND = 0xC000, // Set VX to random number & NN

    // skip key 0xE000 4th nibble mask
    SKIP_KEY_NIBBLE = 0xE000,
    SKIP_IF_KEY_PRESSED = 0x009E, // Skip next instruction if key with value VX is pressed
    SKIP_IF_KEY_NOT_PRESSED = 0x00A1, // Skip next instruction if key with value VX is not pressed

    // timer and I/O instructions 0xF000 4th nibble mask
    MISC_NIBBLE = 0xF000,
    // GET_TIMER = 0x0007, // Set VX to value of delay timer
    SET_TIMER = 0x0015, // Set delay timer to VX
    SET_SOUND_TIMER = 0x0018, // Set sound timer to VX
    ADDI = 0x001E, // Set I to I + VX
    GET_KEY = 0x000A, // Wait for key press and store in VX
    FONT_CHARACTER = 0x0029, // Set I to location of sprite for character in VX
    DECIMAL = 0x0033, // Store BCD representation of VX in memory locations I, I+1, and I+2
    STORE_MEMORY = 0x0055, // Store registers V0 through VX in memory starting at location I
    LOAD_MEMORY = 0x0065, // Read registers V0 through VX from memory starting at location I
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
        lr: bool,
        registerX: u4,
        registerY: u4,
    },
    shiftRight: struct {
        opcode: u16,
        registerX: u4,
        registerY: u4,
    },
    shiftLeft: struct {
        opcode: u16,
        registerX: u4,
        registerY: u4,
    },
    jumpWithOffset: struct {
        opcode: u16,
        address: u12,
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
    skipIfKeyNotPressed: struct {
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

test "Load commands from bytes" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);
    var bytes = [_]u8{ 0x12, 0x34, 0x56, 0x78 };
    c.loadFromBytes(&bytes);
    try std.testing.expectEqual(c.memory[0x200], 0x12);
    try std.testing.expectEqual(c.memory[0x201], 0x34);
    try std.testing.expectEqual(c.memory[0x202], 0x56);
    try std.testing.expectEqual(c.memory[0x203], 0x78);
}

test "Load ROM and check memory contents" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.initWithRom("roms/IBM Logo.ch8", &display);
    var r = try rom.Rom.load("roms/IBM Logo.ch8");
    for (r.data[0..]) |*byte| {
        try std.testing.expect(byte.* == c.memory[c.pc]);
        c.pc += 1;
    }
}

test "Decode CLS" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);
    var opcode: u16 = 0x00E0;
    var i = try c.decode(opcode);
    try std.testing.expect(i.cls.opcode == opcode);
}

test "Decode JMP" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);
    var opcode: u16 = 0x1ABC;
    var i = try c.decode(opcode);
    try std.testing.expect(i.jmp.opcode == opcode);
    try std.testing.expect(i.jmp.address == 0xABC);
}

test "Decode SETVX" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);
    var opcode: u16 = 0x6ABC;
    var i = try c.decode(opcode);
    try std.testing.expect(i.setvx.opcode == opcode);
    try std.testing.expect(i.setvx.register == 0xA);
    try std.testing.expect(i.setvx.value == 0xBC);
}

test "Decode ADDVX" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);
    var opcode: u16 = 0x7ABC;
    var i = try c.decode(opcode);
    try std.testing.expect(i.addvx.opcode == opcode);
    try std.testing.expect(i.addvx.register == 0xA);
    try std.testing.expect(i.addvx.value == 0xBC);
}

test "Decode SETI" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);
    var opcode: u16 = 0xAABC;
    var i = try c.decode(opcode);
    try std.testing.expect(i.seti.opcode == opcode);
    try std.testing.expect(i.seti.address == 0xABC);
}

test "Decode DRAW" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);
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
    var c = try Chip8.init(&display);

    var opcode: u16 = 0x2ABC;
    var i = try c.decode(opcode);
    try std.testing.expect(i.call.opcode == opcode);
    try std.testing.expect(i.call.address == 0xABC);
}

test "Decode RET" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);

    var opcode: u16 = 0x00EE;
    var i = try c.decode(opcode);
    try std.testing.expect(i.ret.opcode == opcode);
}

test "Decode SKIP_IF_EQUAL" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);

    var opcode: u16 = 0x3ABC;
    var i = try c.decode(opcode);
    try std.testing.expect(i.skipIfEqual.opcode == opcode);
    try std.testing.expect(i.skipIfEqual.register == 0xA);
    try std.testing.expect(i.skipIfEqual.value == 0xBC);
}

test "Decode SKIP_IF_NOT_EQUAL" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);

    var opcode: u16 = 0x4ABC;
    var i = try c.decode(opcode);
    try std.testing.expect(i.skipIfNotEqual.opcode == opcode);
    try std.testing.expect(i.skipIfNotEqual.register == 0xA);
    try std.testing.expect(i.skipIfNotEqual.value == 0xBC);
}

test "Decode SKIP_IF_EQUAL_REGISTER" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);

    var program = &[_]u16{0x5AB0};
    c.loadFromArray(program);

    var opcode = c.fetch();
    var i = try c.decode(opcode);
    try std.testing.expect(i.skipIfEqualRegister.opcode == opcode);
    try std.testing.expect(i.skipIfEqualRegister.registerX == 0xA);
    try std.testing.expect(i.skipIfEqualRegister.registerY == 0xB);
}

test "Decode SKIP_IF_NOT_EQUAL_REGISTER" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);

    var opcode: u16 = 0x9AB0;
    var i = try c.decode(opcode);
    try std.testing.expect(i.skipIfNotEqualRegister.opcode == opcode);
    try std.testing.expect(i.skipIfNotEqualRegister.registerX == 0xA);
    try std.testing.expect(i.skipIfNotEqualRegister.registerY == 0xB);
}

test "Decode REGISTER_SET" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);

    var opcode: u16 = 0x8AB0;
    var i = try c.decode(opcode);
    try std.testing.expect(i.registerSet.opcode == opcode);
    try std.testing.expect(i.registerSet.registerX == 0xA);
    try std.testing.expect(i.registerSet.registerY == 0xB);
}

test "Decode AND" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);

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
    var c = try Chip8.init(&display);

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
    var c = try Chip8.init(&display);

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
    var c = try Chip8.init(&display);
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
    var c = try Chip8.init(&display);
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
    var c = try Chip8.init(&display);
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
    var c = try Chip8.init(&display);
    // 0x8AB6
    var opcode: u16 = 0x8AB6;
    var i = try c.decode(opcode);
    try std.testing.expect(i.shiftRight.opcode == opcode);
    try std.testing.expect(i.shiftRight.registerX == 0xA);
    try std.testing.expect(i.shiftRight.registerY == 0xB);
}

test "Decode SHIFT_LEFT" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);
    // 0x8ABE
    var opcode: u16 = 0x8ABE;
    var i = try c.decode(opcode);
    try std.testing.expect(i.shiftLeft.opcode == opcode);
    try std.testing.expect(i.shiftLeft.registerX == 0xA);
    try std.testing.expect(i.shiftLeft.registerY == 0xB);
}

test "Decode JUMP_WITH_OFFSET" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);
    var opcode: u16 = 0xBABC;
    var i = try c.decode(opcode);
    try std.testing.expect(i.jumpWithOffset.opcode == opcode);
    try std.testing.expect(i.jumpWithOffset.address == 0xABC);
}

test "Decode RND" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);
    var opcode: u16 = 0xCABC;
    var i = try c.decode(opcode);
    try std.testing.expect(i.random.opcode == opcode);
    try std.testing.expect(i.random.register == 0xA);
    try std.testing.expect(i.random.value == 0xBC);
}

test "Decode SKIP_IF_KEY_PRESSED" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);
    var program = &[_]u16{0xE0A1};
    c.loadFromArray(program);
    var opcode = c.fetch();
    var i = try c.decode(opcode);
    try std.testing.expect(i.skipIfKeyPressed.opcode == opcode);
    try std.testing.expect(i.skipIfKeyPressed.register == 0x0);
}

test "Decode SKIP_IF_KEY_NOT_PRESSED" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);
    var program = &[_]u16{0xE09E};
    c.loadFromArray(program);
    var opcode = c.fetch();
    var i = try c.decode(opcode);
    try std.testing.expect(i.skipIfKeyPressed.opcode == opcode);
    try std.testing.expect(i.skipIfKeyPressed.register == 0x0);
}

test "Decode GET_TIMER" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);
    var opcode: u16 = 0xFA07;
    var i = try c.decode(opcode);
    try std.testing.expect(i.getDelayTimer.opcode == opcode);
    try std.testing.expect(i.getDelayTimer.register == 0xA);
}

test "Decode SET_TIMER" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);
    var opcode: u16 = 0xFA15;
    var i = try c.decode(opcode);
    try std.testing.expect(i.setDelayTimer.opcode == opcode);
    try std.testing.expect(i.setDelayTimer.register == 0xA);
}

test "Decode SET_SOUND_TIMER" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);
    // 0xFA18
    var opcode: u16 = 0xFA18;
    var i = try c.decode(opcode);
    try std.testing.expect(i.setSoundTimer.opcode == opcode);
    try std.testing.expect(i.setSoundTimer.register == 0xA);
}

test "Decode ADDI" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);
    // 0xFA1E
    var opcode: u16 = 0xFA1E;
    var i = try c.decode(opcode);
    try std.testing.expect(i.addI.opcode == opcode);
    try std.testing.expect(i.addI.register == 0xA);
}

test "Decode GET_KEY" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);
    // 0xFA0A
    var opcode: u16 = 0xFA0A;
    var i = try c.decode(opcode);
    try std.testing.expect(i.getKey.opcode == opcode);
    try std.testing.expect(i.getKey.register == 0xA);
}

test "Decode FONT_CHARACTER" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);
    // 0xFA29
    var opcode: u16 = 0xFA29;
    var i = try c.decode(opcode);
    try std.testing.expect(i.fontCharacter.opcode == opcode);
    try std.testing.expect(i.fontCharacter.register == 0xA);
}

test "Decode BINARY_CODED_DECIMAL" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);
    // 0xFA33
    var opcode: u16 = 0xFA33;
    var i = try c.decode(opcode);
    try std.testing.expect(i.binaryCodedDecimal.opcode == opcode);
    try std.testing.expect(i.binaryCodedDecimal.register == 0xA);
}

test "Decode STORE_MEMORY" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);
    // 0xFA55
    var opcode: u16 = 0xFA55;
    var i = try c.decode(opcode);
    try std.testing.expect(i.storeMemory.opcode == opcode);
    try std.testing.expect(i.storeMemory.register == 0xA);
}

test "Decode LOAD_MEMORY" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);
    // 0xFA65
    var opcode: u16 = 0xFA65;
    var i = try c.decode(opcode);
    try std.testing.expect(i.loadMemory.opcode == opcode);
    try std.testing.expect(i.loadMemory.register == 0xA);
}

test "Execute CLS" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);
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
    var c = try Chip8.init(&display);
    var opcode: u16 = 0x1ABC;
    var i = try c.decode(opcode);
    try c.execute(i);
    try std.testing.expect(c.pc == 0xABC);
}

test "Execute SETVX" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);
    var opcode: u16 = 0x6ABC;
    var i = try c.decode(opcode);
    try c.execute(i);
    try std.testing.expect(c.v[0xA] == 0xBC);
}

test "Execute ADDVX" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);
    c.v[0xA] = 0x01;
    var opcode: u16 = 0x7ABC;
    var i = try c.decode(opcode);
    try c.execute(i);
    try std.testing.expect(c.v[0xA] == 0xBC + 0x01);
}

test "Execute SETI" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);
    var opcode: u16 = 0xAABC;
    var i = try c.decode(opcode);
    try c.execute(i);
    try std.testing.expect(c.i == 0xABC);
}

test "Execute DRAW" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);

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
    var c = try Chip8.init(&display);

    var opcode: u16 = 0x2ABC;
    var i = try c.decode(opcode);
    try c.execute(i);
    try std.testing.expect(c.pc == 0xABC);
    try std.testing.expect(c.stack[0] == 0x200);
}

test "Execute RET" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);

    c.stack[1] = 0xABC;
    c.sp = 1;

    var opcode: u16 = 0x00EE;
    var i = try c.decode(opcode);
    try c.execute(i);
    try std.testing.expect(c.pc == 0xABC);
    try std.testing.expect(c.sp == 0);
}

test "Execute SKIP_IF_EQUAL" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);

    c.v[0xA] = 0xBC;

    // var opcode: u16 = 0x3ABC;
    var program = &[_]u16{0x3ABC};
    c.loadFromArray(program);
    var opcode = c.fetch();
    var i = try c.decode(opcode);
    try c.execute(i);

    try std.testing.expectEqual(c.pc, 0x204);

    c.pc = 0x200;
    c.v[0xA] = 0xAB;
    c.loadFromArray(program);
    opcode = c.fetch();
    try c.execute(i);
    try std.testing.expectEqual(c.pc, 0x202);
}

test "Execute SKIP_IF_NOT_EQUAL" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);

    c.v[0xA] = 0xBC;
    var program = &[_]u16{0x4ABC};
    c.loadFromArray(program);
    var opcode = c.fetch();
    var i = try c.decode(opcode);
    try c.execute(i);
    try std.testing.expect(c.pc == 0x202);

    c.v[0xA] = 0xAB;
    c.pc = 0x200;
    c.loadFromArray(program);
    opcode = c.fetch();
    try c.execute(i);
    try std.testing.expect(c.pc == 0x204);
}

test "Execute SKIP_IF_EQUAL_REGISTER" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);

    c.v[0xA] = 0xBC;
    c.v[0xB] = 0xBC;
    var program = &[_]u16{0x5AB0};
    c.loadFromArray(program);
    var opcode = c.fetch();
    var i = try c.decode(opcode);
    try c.execute(i);
    try std.testing.expect(c.pc == 0x204);

    c.v[0xA] = 0xBC;
    c.v[0xB] = 0xAB;
    c.pc = 0x200;
    c.loadFromArray(program);
    opcode = c.fetch();
    try c.execute(i);
    try std.testing.expect(c.pc == 0x202);
}

test "Execute SKIP_IF_NOT_EQUAL_REGISTER" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);

    c.v[0xA] = 0xBC;
    c.v[0xB] = 0xBC;
    var program = &[_]u16{0x9AB0};
    c.loadFromArray(program);
    var opcode = c.fetch();
    var i = try c.decode(opcode);
    try c.execute(i);
    try std.testing.expect(c.pc == 0x202);

    c.v[0xA] = 0xBC;
    c.v[0xB] = 0xAB;
    c.pc = 0x200;
    c.loadFromArray(program);
    opcode = c.fetch();
    try c.execute(i);
    try std.testing.expect(c.pc == 0x204);
}

test "Execute REGISTER_SET" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);

    c.v[0xA] = 0xBC;
    c.v[0xB] = 0xAB;
    var program = &[_]u16{0x8AB0};
    c.loadFromArray(program);
    var opcode = c.fetch();
    var i = try c.decode(opcode);
    try c.execute(i);
    try std.testing.expect(c.v[0xA] == c.v[0xB]);
}

test "Execute BINARY_AND" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);

    c.v[0xA] = 0b10101010;
    c.v[0xB] = 0b11110000;
    var program = &[_]u16{0x8AB1};
    c.loadFromArray(program);
    var opcode = c.fetch();
    var i = try c.decode(opcode);
    try c.execute(i);
    try std.testing.expect(c.v[0xA] == 0b10100000);
}

test "Execute BINARY_OR" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);

    c.v[0xA] = 0b10101010;
    c.v[0xB] = 0b11110000;
    var program = &[_]u16{0x8AB2};
    c.loadFromArray(program);
    var opcode = c.fetch();
    var i = try c.decode(opcode);
    try c.execute(i);
    try std.testing.expect(c.v[0xA] == 0b11111010);
}

test "Execute BINARY_XOR" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);

    c.v[0xA] = 0b10101010;
    c.v[0xB] = 0b11110000;
    var program = &[_]u16{0x8AB3};
    c.loadFromArray(program);
    var opcode = c.fetch();
    var i = try c.decode(opcode);
    try c.execute(i);
    try std.testing.expect(c.v[0xA] == 0b01011010);
}

test "Execute ADD_REGISTER_NO_CARRY" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);

    c.v[0xA] = 0xFF;
    c.v[0xB] = 0x01;
    var program = &[_]u16{0x8AB4};
    c.loadFromArray(program);
    var opcode = c.fetch();
    var i = try c.decode(opcode);
    try c.execute(i);
    try std.testing.expect(c.v[0xA] == 0x00);
    try std.testing.expect(c.v[0xF] == 1);
}

test "Execute SUBSTRACT_LR" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);

    c.v[0xA] = 10;
    c.v[0xB] = 5;
    var program = &[_]u16{0x8AB5};
    c.loadFromArray(program);
    var opcode = c.fetch();
    var i = try c.decode(opcode);
    try c.execute(i);
    try std.testing.expect(c.v[0xA] == 5);
    try std.testing.expect(c.v[0xF] == 1);
}

test "Execute SUBSTRACT_RL" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);

    c.v[0xA] = 5;
    c.v[0xB] = 10;
    var program = &[_]u16{0x8BA5};
    c.loadFromArray(program);
    var opcode = c.fetch();
    var i = try c.decode(opcode);
    try c.execute(i);
    try std.testing.expect(c.v[0xB] == 5);
    try std.testing.expect(c.v[0xF] == 1);
}

test "Execute SHIFT_RIGHT" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);

    c.v[0xB] = 0b10101010;
    var program = &[_]u16{0x8BB6};
    c.loadFromArray(program);
    var opcode = c.fetch();
    var i = try c.decode(opcode);
    try c.execute(i);
    try std.testing.expect(c.v[0xB] == 0b01010101);
    try std.testing.expect(c.v[0xF] == 0);
}

test "Execute SHIFT_LEFT" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);

    c.v[0xB] = 0b10101010;
    var program = &[_]u16{0x8BBE};
    c.loadFromArray(program);
    var opcode = c.fetch();
    var i = try c.decode(opcode);
    try c.execute(i);
    try std.testing.expect(c.v[0xB] == 0b01010100);
    try std.testing.expect(c.v[0xF] == 1);
}

test "Execute JUMP_WITH_OFFSET" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);

    c.v[0x0] = 0x01;
    var program = &[_]u16{0xBABC};
    c.loadFromArray(program);
    var opcode = c.fetch();
    var i = try c.decode(opcode);
    try c.execute(i);
    try std.testing.expectEqual(c.pc, 0xABC + 0x01);
}

test "Execute RND" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);

    var program = &[_]u16{0xCABC};
    c.loadFromArray(program);
    var opcode = c.fetch();
    var i = try c.decode(opcode);
    try c.execute(i);
    try std.testing.expect(c.v[0xA] != 0);
}

test "Execute GET_DELAY_TIMER" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);

    c.delayTimer = 0x01;
    var program = &[_]u16{0xFA07};
    c.loadFromArray(program);
    var opcode = c.fetch();
    var i = try c.decode(opcode);
    try c.execute(i);
    try std.testing.expectEqual(c.v[0xA], 0x01);
}

test "Execute SET_DELAY_TIMER" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);

    c.v[0xA] = 0x01;
    var program = &[_]u16{0xFA15};
    c.loadFromArray(program);
    var opcode = c.fetch();
    var i = try c.decode(opcode);
    try c.execute(i);
    try std.testing.expectEqual(c.delayTimer, 0x01);
}

test "Execute SET_SOUND_TIMER" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);

    c.v[0xA] = 0x01;
    var program = &[_]u16{0xFA18};
    c.loadFromArray(program);
    var opcode = c.fetch();
    var i = try c.decode(opcode);
    try c.execute(i);
    try std.testing.expectEqual(c.soundTimer, 0x01);
}

test "Execute ADDI" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);

    c.i = 0x01;
    c.v[0xA] = 0x01;
    var program = &[_]u16{0xFA1E};
    c.loadFromArray(program);
    var opcode = c.fetch();
    var i = try c.decode(opcode);
    try c.execute(i);
    try std.testing.expectEqual(c.i, 0x02);
}

test "Execute FONT_CHARACTER" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);

    c.v[0xA] = 0x5;
    var program = &[_]u16{0xFA29};
    c.loadFromArray(program);
    var opcode = c.fetch();
    var i = try c.decode(opcode);
    try c.execute(i);
    try std.testing.expectEqual(c.i, 0x05);
    try std.testing.expectEqual(c.memory[c.i], font.font[5]);
}

test "Execute BINARY_CODED_DECIMAL" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);

    c.v[0xA] = 123;
    var program = &[_]u16{0xFA33};
    c.loadFromArray(program);
    var opcode = c.fetch();
    var i = try c.decode(opcode);
    try c.execute(i);
    try std.testing.expectEqual(c.memory[c.i], 1);
    try std.testing.expectEqual(c.memory[c.i + 1], 2);
    try std.testing.expectEqual(c.memory[c.i + 2], 3);
}

test "Execute STORE_MEMORY" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);

    c.v[0] = 1;
    c.v[1] = 2;
    c.v[2] = 3;
    c.v[3] = 4; // we won't store this one
    c.i = 0x200;
    var program = &[_]u16{0xF355}; // store 3 registers starting at 0x200
    c.loadFromArray(program);
    var opcode = c.fetch();
    var i = try c.decode(opcode);
    try c.execute(i);
    try std.testing.expectEqual(c.memory[0x200], 1);
    try std.testing.expectEqual(c.memory[0x201], 2);
    try std.testing.expectEqual(c.memory[0x202], 3);
    try std.testing.expect(c.memory[0x203] != 4);
}

test "Execute LOAD_MEMORY" {
    var display = try dsp.Display.init();
    defer display.destroy();
    var c = try Chip8.init(&display);

    c.memory[0x300] = 0x1;
    c.memory[0x301] = 0x2;
    c.memory[0x302] = 0x3;

    std.log.err("\n0x200 mem value {}\n", .{c.memory[0x200]});
    c.i = 0x300;
    var program = &[_]u16{0xF265}; // load 3 registers starting at 0x200
    c.loadFromArray(program);
    var opcode = c.fetch();
    var i = try c.decode(opcode);
    try c.execute(i);
    std.log.err("\n{}\n", .{c.v[0]});
    try std.testing.expectEqual(c.v[0], 1);
    try std.testing.expectEqual(c.v[1], 2);
    try std.testing.expect(c.v[2] != 3);
}
