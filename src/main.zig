const dsp = @import("display.zig");
const emu = @import("chip8.zig");

pub fn main() !void {
    var display = try dsp.Display.init();
    // var chip8 = try emu.Chip8.initWithRom("roms/IBM Logo.ch8", &display);
    // var chip8 = try emu.Chip8.initWithRom("roms/Test Opcode.ch8", &display);
    var chip8 = try emu.Chip8.initWithRom("roms/Pong ROM.ch8", &display);
    defer display.destroy();

    try display.clearScreen();

    try display.playBeep();

    while (true) {
        try chip8.cycle();
        try display.renderLoop();

        if (display.shouldQuit()) {
            break;
        }
    }
}
