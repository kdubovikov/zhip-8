const dsp = @import("display.zig");
const emu = @import("chip8.zig");
const std = @import("std");

const err = error.InitError;
const fps: u64 = (1 / 60 * 1000);
const ipf: u64 = 100;

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

    var lastTime = display.getTicks();
    while (true) {
        const diff = (display.getTicks() - lastTime);

        chip8.updateTimers(display.getTicks());
        // std.debug.print("Running {d}\n", .{diff});
        if (diff > fps) {
            try display.handleInput();
            for (0..ipf) |i| {
                _ = i;
                try chip8.cycle(false);
            }
            try display.render();
            lastTime = display.getTicks();
        }

        if (display.shouldQuit()) {
            break;
        }
    }
}
