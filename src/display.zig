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

const math = std.math;

const Amplitude = 28000;
const SampleRate = 44100;
const Frequency = 441.0;

var sample_nr: i32 = 0;

/// Format a floating point audio signal to a 16-bit integer.
fn formatSignal(signal: f64) u16 {
    var result = Amplitude * signal;
    if (result < 0.0) result = 0.0;
    if (result > 65535.0) result = 65535.0;
    return @as(u16, @intFromFloat(result));
}

/// Audio callback function for SDL Audio. Generates a sine wave.
fn audioCallback(user_data: ?*anyopaque, raw_buffer: [*c]u8, bytes: c_int) callconv(.C) void {
    _ = user_data;
    const bufLen: usize = @intCast(bytes);
    var buffer: [*]u16 = @alignCast(@ptrCast(raw_buffer[0 .. bufLen / 2]));
    for (buffer, 0..bufLen / 2) |*sample, i| {
        _ = i;
        const time: f64 = @as(f64, @floatFromInt(sample_nr)) / @as(f64, @floatFromInt(SampleRate));
        sample.* = formatSignal(math.sin(2.0 * math.pi * Frequency * time));
        sample_nr += 1;
    }
}

pub const Display = struct {
    window: *c.SDL_Window,
    renderer: *c.SDL_Renderer,
    screen: *c.SDL_Texture,
    pixels: [displayWidth * displayHeight * 4]u32,
    should_quit: bool,
    beep_sound: *c.SDL_AudioSpec,
    audio_device: *c.SDL_AudioDeviceID,

    const Self = @This();

    pub fn init() DisplayError!Self {
        try sdlErr(c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_AUDIO));

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

        // var audio_device: c.SDL_AudioDeviceID = undefined;
        // _ = audio_device;
        const callback: (?*const fn (?*anyopaque, [*c]u8, c_int) callconv(.C) void) = &audioCallback;
        var audio_spec: c.SDL_AudioSpec = c.SDL_AudioSpec{
            .freq = 44100,
            .format = c.AUDIO_S16LSB,
            .channels = 1,
            .silence = 0,
            .samples = 4096,
            .padding = 0,
            .size = 0,
            .callback = callback,
            .userdata = null,
        };

        return Self{ .should_quit = false, .window = window, .renderer = renderer, .screen = texture, .pixels = pixels, .beep_sound = &audio_spec, .audio_device = undefined };
    }

    pub fn playBeep(self: *Self) !void {
        var obtained_spec: c.SDL_AudioSpec = undefined;

        const err = c.SDL_OpenAudio(self.beep_sound, &obtained_spec);
        if (err != 0) {
            std.debug.print("SDL_OpenAudio Error: {s}\n", .{c.SDL_GetError()});
            return DisplayError.InitError;
        }
        c.SDL_PauseAudio(0);
        c.SDL_Delay(500);
        c.SDL_CloseAudio();
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
        // c.SDL_CloseAudioDevice(self.audio_device.*);
        // c.SDL_FreeWAV();
        c.SDL_Quit();
    }
};
