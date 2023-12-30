const std = @import("std");
const c = @cImport({
    @cInclude("SDL2/SDL.h");
});

pub const displayWidth = 64;
pub const displayHeight = 32;

pub const DisplayError = error{InitError};
pub const PixelState = enum { on, off };

fn sdlErr(result: c_int) !void {
    if (result != 0) {
        std.debug.print("SDL Error: {s}\n", .{c.SDL_GetError()});
        return error.InitError;
    }
}

pub const Display = struct {
    window: *c.SDL_Window,
    renderer: *c.SDL_Renderer,
    screen: *c.SDL_Texture,
    pixels: [displayWidth * displayHeight * 4]u32,
    should_quit: bool,

    const Self = @This();

    pub fn init() DisplayError!Self {
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

        return Self{ .should_quit = false, .window = window, .renderer = renderer, .screen = texture, .pixels = pixels };
    }

    pub fn shouldQuit(self: Self) bool {
        return self.should_quit;
    }

    /// Set a pixel to on or off at the given coordinates and return the previous state.
    pub fn setPixel(self: *Self, x: usize, y: usize) !bool {
        var ret: bool = false;

        // if ((x >= displayWidth) or (y >= displayHeight)) {
        //     return error.InitError;
        // }

        const index: usize = y * displayWidth + x;
        if (self.pixels[index] == 0xFFFFFFFF) {
            ret = true;
        }
        self.pixels[index] = if (self.pixels[index] == 0) 0xFFFFFFFF else 0;
        return ret;
    }

    /// Print all pixels to stdout.
    fn printPixels(self: Self) void {
        // print all pixels as table
        for (0..displayHeight) |yy| {
            for (0..displayWidth) |xx| {
                var p = self.pixels[yy * displayWidth + xx];
                if (p == 0xFFFFFFFF) {
                    std.debug.print("X", .{});
                } else {
                    std.debug.print(" ", .{});
                }
            }
            std.debug.print("\n", .{});
        }
    }

    /// Clear the screen by setting all pixels to off.
    pub fn clearScreen(self: *Self) !void {
        for (self.pixels[0..]) |*pixel| {
            pixel.* = 0;
        }
    }

    pub fn renderLoop(self: *Self) !void {
        var sdl_event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&sdl_event) != 0) {
            switch (sdl_event.type) {
                c.SDL_QUIT => self.should_quit = true,
                else => {},
            }
        }

        try sdlErr(c.SDL_RenderClear(self.renderer));
        try sdlErr(c.SDL_UpdateTexture(self.screen, null, self.pixels[0..].ptr, displayWidth * @sizeOf(u32)));
        try sdlErr(c.SDL_RenderCopy(self.renderer, self.screen, null, null));
        c.SDL_RenderPresent(self.renderer);
    }

    pub fn destroy(self: Self) void {
        c.SDL_DestroyTexture(self.screen);
        c.SDL_DestroyRenderer(self.renderer);
        c.SDL_DestroyWindow(self.window);
        c.SDL_Quit();
    }
};
