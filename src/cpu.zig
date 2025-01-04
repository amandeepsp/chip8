const Memory = @import("memory.zig").Memory;
const std = @import("std");
const log = std.log;
const RandGen = std.rand.DefaultPrng;

pub const Cpu = struct {
    v: [16]u8 = [_]u8{0} ** 16,
    i: u12 = 0,
    pc: u12 = 0x200,
    stack: [16]u12 = [_]u12{0} ** 16,
    sp: u8 = 0,
    delay_timer: u8 = 0,
    sound_timer: u8 = 0,
    gfx: [64 * 32]u8 = [_]u8{0} ** 2048,
    draw_flag: bool = false,
    keys: [16]bool = [_]bool{false} ** 16,
    random_generator: RandGen = RandGen.init(0),
    wait_for_keypress: bool = false,

    pub fn init() Cpu {
        return Cpu{};
    }

    fn exec_special(self: *Cpu, opcode: u16) void {
        switch (opcode) {
            0x00E0 => {
                // clear screen
                for (0..2048) |i| {
                    self.gfx[i] = 0;
                }
                self.draw_flag = true;
            },
            0x00EE => {
                // return from subroutine
                self.sp -= 1;
                self.pc = self.stack[self.sp];
            },
            else => {
                // call machine code routine at NNN
                // not implemented
                log.err("Unimplemented Opcode: {x}", .{opcode});
            },
        }
    }

    fn exec_draw(self: *Cpu, opcode: u16, memory: *Memory) void {
        // draw sprite at (Vx, Vy) with width 8 and height N
        const n2: u8 = @truncate((opcode & 0x0F00) >> 8);
        const n3: u8 = @truncate((opcode & 0x00F0) >> 4);
        const x: u8 = self.v[n2] % 64;
        const y: u8 = self.v[n3] % 32;
        const height = opcode & 0x000F;
        self.v[0xF] = 0;
        for (0..height) |i| {
            const byte = memory.read_addr(@truncate(self.i + i));
            for (0..8) |j| {
                const bit_value = (byte >> @intCast(7 - j)) & 0x1;
                const y_coord = (y + i) % 32;
                const x_coord = (x + j) % 64;
                const index = y_coord * 64 + x_coord;
                if (bit_value == 1 and self.gfx[index] == 1) {
                    self.v[0xF] = 1;
                }
                self.gfx[index] ^= bit_value;
            }
        }
        self.draw_flag = true;
    }

    fn exec_key(self: *Cpu, opcode: u16) void {
        const n2: u8 = @truncate((opcode & 0x0F00) >> 8);
        const key_press = self.keys[self.v[n2]];
        switch (opcode & 0x00FF) {
            0x9E => {
                // skip next instruction if key with the value of Vx is pressed
                if (key_press) {
                    self.pc += 2;
                }
            },
            0xA1 => {
                // skip next instruction if key with the value of Vx is not pressed
                if (!key_press) {
                    self.pc += 2;
                }
            },
            else => {
                // unknown opcode
                log.err("Unknown opcode: {x}:", .{opcode});
            },
        }
    }

    fn exec_misc(self: *Cpu, opcode: u16, memory: *Memory) void {
        const n2: u8 = @truncate((opcode & 0x0F00) >> 8);
        switch (opcode & 0x00FF) {
            0x07 => {
                // set Vx = delay timer value
                self.v[n2] = self.delay_timer;
            },
            0x0A => {
                // wait for a key press, store the value of the key in Vx
                self.wait_for_keypress = true;
                //self.pc -= 2;
            },
            0x15 => {
                // set delay timer = Vx
                self.delay_timer = self.v[n2];
            },
            0x18 => {
                // set sound timer = Vx
                self.sound_timer = self.v[n2];
            },
            0x1E => {
                // set I = I + Vx
                self.i += self.v[n2];
            },
            0x29 => {
                // set I = location of sprite for digit Vx
                self.i = @intCast(self.v[n2] * 5);
            },
            0x33 => {
                // store BCD representation of Vx in memory locations I, I+1, I+2
                const value = self.v[n2];
                memory.write_addr(self.i, value / 100);
                memory.write_addr(self.i + 1, (value / 10) % 10);
                memory.write_addr(self.i + 2, value % 10);
            },
            0x55 => {
                // store registers V0 through Vx in memory starting at location I
                for (0..n2 + 1) |i| {
                    const offset: u12 = @truncate(i);
                    memory.write_addr(self.i + offset, self.v[i]);
                }
            },
            0x65 => {
                // read registers V0 through Vx from memory starting at location I
                for (0..n2 + 1) |i| {
                    self.v[i] = memory.read_addr(self.i + @as(u12, @truncate(i)));
                }
            },
            else => {
                // unknown opcode
                log.err("Unknown opcode: {x}", .{opcode});
            },
        }
    }

    pub fn tick(self: *Cpu, memory: *Memory) void {
        const mem_byte1 = @as(u16, memory.read_addr(self.pc));
        const mem_byte2 = @as(u16, memory.read_addr(self.pc + 1));
        const opcode = (mem_byte1 << 8) | mem_byte2;

        const n1: u8 = @truncate((opcode & 0xF000) >> 12);
        const n2: u8 = @truncate((opcode & 0x0F00) >> 8);
        const n3: u8 = @truncate((opcode & 0x00F0) >> 4);
        const n4: u8 = @truncate(opcode & 0x000F);

        if (self.wait_for_keypress) {
            log.debug("Waiting for keypress", .{});
            for (self.keys, 0..) |key, i| {
                if (key) {
                    log.debug("Key pressed: {x}", .{i});
                    self.v[n2] = @intCast(i & 0xF);
                    self.wait_for_keypress = false;
                    break;
                }
            }

            if (self.wait_for_keypress) {
                // skip this cycle
                return;
            }
        }

        self.pc += 2;

        switch (n1) {
            0x0 => {
                self.exec_special(opcode);
            },
            0x1 => {
                // jump to address NNN
                self.pc = @truncate(opcode & 0x0FFF);
            },
            0x2 => {
                // call subroutine at address NNN
                self.stack[self.sp] = self.pc;
                self.sp += 1;
                self.pc = @truncate(opcode & 0x0FFF);
            },
            0x3 => {
                // skip next instruction if Vx == NN
                if (self.v[n2] == opcode & 0x00FF) {
                    self.pc += 2;
                }
            },
            0x4 => {
                // skip next instruction if Vx != NN
                if (self.v[n2] != opcode & 0x00FF) {
                    self.pc += 2;
                }
            },
            0x5 => {
                // skip next instruction if Vx == Vy
                if (self.v[n2] == self.v[n3]) {
                    self.pc += 2;
                }
            },
            0x6 => {
                // set Vx = NN
                self.v[n2] = @truncate(opcode & 0x00FF);
            },
            0x7 => {
                // set Vx = Vx + NN
                self.v[n2] = @truncate(self.v[n2] +% opcode & 0x00FF);
            },
            0x8 => {
                switch (n4) {
                    0x0 => {
                        // set Vx = Vy
                        self.v[n2] = self.v[n3];
                    },
                    0x1 => {
                        // set Vx = Vx | Vy
                        self.v[n2] |= self.v[n3];
                    },
                    0x2 => {
                        // set Vx = Vx & Vy
                        self.v[n2] &= self.v[n3];
                    },
                    0x3 => {
                        // set Vx = Vx ^ Vy
                        self.v[n2] ^= self.v[n3];
                    },
                    0x4 => {
                        // set Vx = Vx + Vy, set VF = carry
                        if (self.v[n3] > (0xFF - self.v[n2])) {
                            self.v[0xF] = 1;
                        } else {
                            self.v[0xF] = 0;
                        }
                        self.v[n2] +%= self.v[n3];
                    },
                    0x5 => {
                        // set Vx = Vx - Vy, set VF = NOT borrow
                        if (self.v[n2] > self.v[n3]) {
                            self.v[0xF] = 1;
                        } else {
                            self.v[0xF] = 0;
                        }

                        self.v[n2] -%= self.v[n3];
                    },
                    0x6 => {
                        // set Vx = Vx >> 1, set VF = LSB of Vx
                        self.v[0xF] = self.v[n2] & 0x1;
                        self.v[n2] >>= 1;
                    },
                    0x7 => {
                        // set Vx = Vy - Vx, set VF = NOT borrow
                        if (self.v[n3] > self.v[n2]) {
                            self.v[0xF] = 1;
                        } else {
                            self.v[0xF] = 0;
                        }
                        self.v[n2] = self.v[n3] -% self.v[n2];
                    },
                    0xE => {
                        // set Vx = Vx << 1, set VF = MSB of Vx
                        self.v[0xF] = self.v[n2] >> 7;
                        self.v[n2] <<= 1;
                    },
                    else => {
                        log.err("Unknown opcode: {x}", .{opcode});
                    },
                }
            },
            0x9 => {
                // skip next instruction if Vx != Vy
                if (self.v[n2] != self.v[n3]) {
                    self.pc += 2;
                }
            },
            0xA => {
                // set I = NNN
                self.i = @truncate(opcode & 0x0FFF);
            },
            0xB => {
                // jump to address NNN + V0
                //self.pc = @truncate(opcode & 0x0FFF + @as(u16, self.v[0]));
                self.pc = @truncate((opcode & 0x0FFF) + @as(u16, self.v[n2]));
            },
            0xC => {
                // set Vx = random byte & NN
                self.v[n2] = @truncate(self.random_generator.random().int(u8) & (opcode & 0x00FF));
            },
            0xD => {
                self.exec_draw(opcode, memory);
            },
            0xE => {
                self.exec_key(opcode);
            },
            0xF => {
                self.exec_misc(opcode, memory);
            },
            else => {
                log.err("Unknown opcode: {x}", .{opcode});
            },
        }
    }

    pub fn timer_tick(self: *Cpu) void {
        if (self.delay_timer > 0) {
            self.delay_timer -= 1;
        }

        if (self.sound_timer > 0) {
            self.sound_timer -= 1;
        }
    }
};
