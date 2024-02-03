const dsp = @import("display.zig");
const emu = @import("chip8.zig");
const std = @import("std");

const err = error.InitError;

pub fn main() !void {
    const alloc: std.mem.Allocator = std.heap.page_allocator;
    var args = try std.process.argsWithAllocator(alloc);
    defer args.deinit();

    var display = try dsp.Display.init();
    // var chip8 = try emu.Chip8.initWithRom("roms/IBM Logo.ch8", &display);
    // var chip8 = try emu.Chip8.initWithRom("roms/Test Opcode.ch8", &display);
    _ = args.next() orelse return err;
    var romPath: []const u8 = args.next() orelse return err;
    std.debug.print("Loading ROM: {s}\n", .{romPath});

    var chip8 = try emu.Chip8.initWithRom(romPath, &display);
    defer display.destroy();

    try display.clearScreen();

    // try display.playBeep();

    while (true) {
        try chip8.cycle();

        try display.renderLoop();

        if (display.shouldQuit()) {
            break;
        }
    }
}
