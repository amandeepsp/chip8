const std = @import("std");
const rl = @import("raylib");
const log = std.log;
const Memory = @import("memory.zig").Memory;
const Cpu = @import("cpu.zig").Cpu;
const Frontend = @import("frontend.zig").Frontend;

const cpu_tick_duration_ms: i64 = 2; //500hz

fn load_rom_from_file(path: []const u8, allocator: *const std.mem.Allocator) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
    defer file.close();

    const file_size = try file.getEndPos();

    const rom = allocator.alloc(u8, file_size) catch {
        return error.OutOfMemory;
    };

    _ = try file.readAll(rom);

    return rom;
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        log.err("Usage: {s} <rom_path>", .{args[0]});
        return error.InvalidArgument;
    }

    const rom_path = args[1];

    var memory = Memory.init();
    var cpu = Cpu.init();
    var frontend = try Frontend.init(640, 320);
    defer frontend.deinit();

    const rom = try load_rom_from_file(rom_path, &allocator);

    memory.load_rom(rom);

    var last_time = std.time.milliTimestamp();
    var accumulated_cpu_time: i64 = 0;

    while (!rl.windowShouldClose()) {
        const current_time = std.time.milliTimestamp();

        frontend.handle_input(&cpu);

        const delta_time = current_time - last_time;
        last_time = current_time;
        accumulated_cpu_time += delta_time;
        while (accumulated_cpu_time >= cpu_tick_duration_ms) {
            cpu.tick(&memory);
            accumulated_cpu_time -= cpu_tick_duration_ms;
        }

        cpu.timer_tick();
        frontend.render_tick(&cpu);
    }
}
