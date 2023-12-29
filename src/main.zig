const dsp = @import("display.zig");
const emu = @import("chip8.zig");

pub fn main() !void {
    var display = try dsp.Display.init();
    var chip8 = try emu.Chip8.init("roms/IBM Logo.ch8", &display);
    _ = chip8;
    defer display.destroy();

    try display.setPixel(32, 20, dsp.PixelState.on);
    try display.renderLoop();
}
