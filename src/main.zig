const std = @import("std");
const c = @cImport({
    @cInclude("SDL2/SDL.h");
});

const memSize: usize = 4096; // 4 KB
const displayWidth = 64;
const displayHeight = 32;

const Memory = struct {
    memory: [memSize]u8,

    fn init() Memory {
        var mem: [memSize]u8 = undefined;
        for (mem[0..]) |*byte| {
            byte.* = 0;
        }

        return Memory{ .memory = mem };
    }
};

test "memory init" {
    var memory = Memory.init();
    try std.testing.expect(memory.memory[0] == 0);
    try std.testing.expect(memory.memory[memSize - 1] == 0);
}

const DisplayError = error{InitError};

fn sdlErr(result: c_int) !void {
    if (result != 0) {
        std.debug.print("SDL Error: {s}\n", .{c.SDL_GetError()});
        return error.InitError;
    }
}

const PixelState = enum { on, off };

const Display = struct {
    window: *c.SDL_Window,
    renderer: *c.SDL_Renderer,
    screen: *c.SDL_Texture,
    pixels: [displayWidth * displayHeight * 4]u32,

    const Self = @This();

    fn init() DisplayError!Self {
        try sdlErr(c.SDL_Init(c.SDL_INIT_VIDEO));

        var window = c.SDL_CreateWindow("ZHIP-8", c.SDL_WINDOWPOS_CENTERED, c.SDL_WINDOWPOS_CENTERED, 640, 320, c.SDL_WINDOW_SHOWN) orelse {
            std.debug.print("SDL_CreateWindow Error: {s}\n", .{c.SDL_GetError()});
            return DisplayError.InitError;
        };

        var renderer = c.SDL_CreateRenderer(window, 0, c.SDL_RENDERER_ACCELERATED | c.SDL_RENDERER_PRESENTVSYNC) orelse {
            std.debug.print("SDL_CreateRenderer Error: {s}\n", .{c.SDL_GetError()});
            return DisplayError.InitError;
        };

        var texture = c.SDL_CreateTexture(renderer, c.SDL_PIXELFORMAT_ARGB8888, c.SDL_TEXTUREACCESS_STREAMING, displayWidth, displayHeight) orelse {
            std.debug.print("SDL_CreateTexture Error: {s}\n", .{c.SDL_GetError()});
            return DisplayError.InitError;
        };

        var pixels: [displayWidth * displayHeight * 4]u32 = undefined;
        for (pixels[0..]) |*pixel| {
            pixel.* = 0;
        }

        return Self{ .window = window, .renderer = renderer, .screen = texture, .pixels = pixels };
    }

    fn setPixel(self: *Self, x: usize, y: usize, state: PixelState) void {
        self.pixels[y * displayWidth + x] = if (state == PixelState.on) 0xFFFFFFFF else 0x00000000;

        // print all pixels as table
        // for (0..displayHeight) |yy| {
        //     for (0..displayWidth) |xx| {
        //         var p = self.pixels[yy * displayWidth + xx];
        //         if (p == 0xFFFFFFFF) {
        //             std.debug.print("X", .{});
        //         } else {
        //             std.debug.print(" ", .{});
        //         }
        //     }
        //     std.debug.print("\n", .{});
        // }
    }

    fn renderLoop(self: Self) !void {
        mainloop: while (true) {
            var sdl_event: c.SDL_Event = undefined;
            while (c.SDL_PollEvent(&sdl_event) != 0) {
                switch (sdl_event.type) {
                    c.SDL_QUIT => break :mainloop,
                    else => {},
                }
            }

            try sdlErr(c.SDL_RenderClear(self.renderer));
            try sdlErr(c.SDL_UpdateTexture(self.screen, null, self.pixels[0..].ptr, displayWidth * @sizeOf(u32)));
            try sdlErr(c.SDL_RenderCopy(self.renderer, self.screen, null, null));
            c.SDL_RenderPresent(self.renderer);
        }
    }

    fn destroy(self: Self) void {
        c.SDL_DestroyTexture(self.screen);
        c.SDL_DestroyRenderer(self.renderer);
        c.SDL_DestroyWindow(self.window);
        c.SDL_Quit();
    }
};

pub fn main() !void {
    var display = try Display.init();
    defer display.destroy();

    display.setPixel(32, 20, PixelState.on);
    try display.renderLoop();
}
