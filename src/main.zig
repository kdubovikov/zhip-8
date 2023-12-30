const dsp = @import("display.zig");
const emu = @import("chip8.zig");

pub fn main() !void {
    var display = try dsp.Display.init();
    var chip8 = try emu.Chip8.init("roms/IBM Logo.ch8", &display);
    defer display.destroy();

    try display.clearScreen();

    while (true) {
        try chip8.cycle();
        try display.renderLoop();

        if (display.shouldQuit()) {
            break;
        }
    }
}
