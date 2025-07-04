const std = @import("std");
const rl = @import("raylib");
const Cpu = @import("cpu.zig").Cpu;
const log = std.log;

const keys = [_]rl.KeyboardKey{
    .x, //0
    .one, //1
    .two, //2
    .three, //3
    .q, //4
    .w, //5
    .e, //6
    .a, //7
    .s, //8
    .d, //9
    .z, //a
    .c, //b
    .four, //c
    .r, //d
    .f, //e
    .v, //f
};

pub const Frontend = struct {
    screenHeight: u32,
    screenWidth: u32,
    pixelWidth: u32,
    pixelHeight: u32,
    frame: rl.RenderTexture2D,
    beep: rl.Sound,
    isBeeping: bool = false,

    pub fn init(screenWidth: u32, screenHeight: u32) !Frontend {
        rl.initWindow(@intCast(screenWidth), @intCast(screenHeight), "Chip8");
        rl.initAudioDevice();
        rl.setTargetFPS(60);

        if (rl.isWindowReady()) {
            log.debug("Window ready", .{});
        } else {
            return error.Unavailable;
        }

        if ((screenWidth % 64 != 0) or (screenHeight % 32 != 0)) {
            log.err("Invalid resolution, must be a multiple of 64x32", .{});
            return error.InvalidResolution;
        }

        const frame = try rl.loadRenderTexture(@intCast(screenWidth), @intCast(screenHeight));

        const beepSound = generateBeep();

        return Frontend{
            .screenWidth = screenWidth,
            .screenHeight = screenHeight,
            .pixelWidth = screenWidth / 64,
            .pixelHeight = screenHeight / 32,
            .frame = frame,
            .beep = beepSound,
        };
    }

    pub fn handle_input(_: *Frontend, cpu: *Cpu) void {
        for (keys, 0..) |key, i| {
            cpu.keys[i] = rl.isKeyDown(key);
        }
    }

    pub fn render_tick(self: *Frontend, cpu: *Cpu) void {
        if (cpu.draw_flag) {
            rl.beginTextureMode(self.frame);
            rl.clearBackground(rl.Color.black);
            self.renderGfx(cpu);
            rl.endTextureMode();
            cpu.draw_flag = false;
        }
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.black);
        rl.drawTextureRec(
            self.frame.texture,
            rl.Rectangle{
                .x = 0,
                .y = 0,
                .width = @floatFromInt(self.screenWidth),
                .height = -@as(f32, @floatFromInt(self.screenHeight)),
            },
            rl.Vector2{ .x = 0, .y = 0 },
            rl.Color.white,
        );

        if (cpu.sound_timer > 0 and !self.isBeeping) {
            rl.playSound(self.beep);
            self.isBeeping = true;
        } else if (cpu.sound_timer == 0 and self.isBeeping) {
            rl.stopSound(self.beep);
            self.isBeeping = false;
        }
    }

    fn renderGfx(self: *Frontend, cpu: *Cpu) void {
        for (0..31) |y| {
            for (0..63) |x| {
                const pixel = cpu.gfx[(y * 64) + x];
                const color = if (pixel != 0) rl.Color.white else rl.Color.black;
                const rect = rl.Rectangle{
                    .x = @floatFromInt(x * self.pixelWidth),
                    .y = @floatFromInt(y * self.pixelHeight),
                    .width = @floatFromInt(self.pixelWidth),
                    .height = @floatFromInt(self.pixelHeight),
                };
                rl.drawRectangleRec(rect, color);
            }
        }
    }

    fn generateBeep() rl.Sound {
        return rl.loadSoundFromWave(rl.loadWave("assets/beep.wav") catch unreachable);
    }

    pub fn deinit(self: *Frontend) void {
        self.screenWidth = 0;
        self.screenHeight = 0;
        rl.unloadSound(self.beep);
        rl.unloadRenderTexture(self.frame);
        rl.closeAudioDevice();
        rl.closeWindow();
    }
};
