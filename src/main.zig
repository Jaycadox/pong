const std = @import("std");
const r = @cImport({
    @cInclude("raylib.h");
});
const rm = @cImport({
    @cInclude("raymath.h");
});

fn floatSign(x: f32) f32 {
    if (x >= 0.0) {
        return 1.0;
    }
    return -1.0;
}

const powerUp = @embedFile("./powerUp.wav");
const ballHit = @embedFile("./ballHit.wav");
const death = @embedFile("./death.wav");

const Ball = struct {
    position: rm.Vector2,
    velocity: rm.Vector2,
    has_power: bool,

    pub fn handle_movement(self: *Ball, players: []const* Player, sounds: *SoundDirectory) void {
        self.position = rm.Vector2Add(self.position, self.velocity);
        for (players) |player| {
            if (@abs(self.position.x - player.position.x) < 20.0) {
                var hit = false;
                if (self.position.y > player.position.y and self.position.y < (player.position.y + 80)) {
                    hit = true;
                } else if (@abs(self.position.y - player.position.y) < 10.0 or @abs(self.position.y - (player.position.y + 80)) < 10.0) {
                    hit = true;
                }

                if (hit) {
                    r.PlaySound(sounds.ballHit);
                    self.velocity.x *= -1.1;
                    self.velocity.y *= 1.1;
                    self.position.x = player.position.x + (20.0 * floatSign(self.velocity.x));
                    if (r.IsKeyDown(player.down_key)) {
                        self.velocity.y += 1.0;
                    }

                    if (r.IsKeyDown(player.up_key)) {
                        self.velocity.y -= 1.0;
                    }

                    if (self.has_power and !player.has_powerup) {
                        player.has_powerup = true;
                        self.has_power = false;
                    }
                }
            }
        }

        if (self.position.y < 10.0) {
            r.PlaySound(sounds.ballHit);
            self.velocity.y *= -1.0;
        }

        if (self.position.y >= (@as(f32, @floatFromInt(r.GetScreenHeight())) - 10.0)) {
            r.PlaySound(sounds.ballHit);
            self.velocity.y *= -1.0;
        }
        const screen_width = @as(f32, @floatFromInt(r.GetScreenWidth()));
        if (self.position.x < 0.0 or self.position.x > screen_width) {
            r.PlaySound(sounds.death);
            // Any player whose x position is more than half the screen away will be awarded a point
            const half_screen = screen_width / 2.0;
            for (players) |player| {
                if (@abs(self.position.x - player.position.x) > half_screen) {
                    player.score += 1;
                    player.has_powerup = false;
                } else {
                    player.has_powerup = true;
                }
            }
            self.has_power = false;

            self.velocity = rm.Vector2 {
                .x = -3.0,
                .y = -3.0,
            };

            self.position = rm.Vector2 {
                .x = half_screen,
                .y = @as(f32, @floatFromInt(r.GetScreenHeight())) / @as(f32, 2.0),
            };
        }
    }
    pub fn render(self: *Ball) void {
        var colour = r.WHITE;
        if (self.has_power) {
            colour = r.YELLOW;
        }
        r.DrawCircle(@intFromFloat(self.position.x), @intFromFloat(self.position.y), 10.0, colour);
    }
};

const Player = struct {
    position: rm.Vector2,
    score: u32,
    up_key: c_int,
    down_key: c_int,
    powerup_key: c_int,
    has_powerup: bool,
    visual_offset: f32,
    ai: bool,
    pub fn init(pos_x: f32, up_key: c_int, down_key: c_int, powerup_key: c_int, ai: bool) Player {
        return Player {
            .position = rm.Vector2 {
                .x = pos_x,
                .y = 30.0
            },
            .score = 0,
            .up_key = up_key,
            .down_key = down_key,
            .powerup_key = powerup_key,
            .has_powerup = false,
            .visual_offset = 0.0,
            .ai = ai,
        };
    }

    pub fn handle_inputs(self: *Player) void {
        if (r.IsKeyDown(self.down_key)) {
            self.position.y += 8;
        }


        if (r.IsKeyDown(self.up_key)) {
            self.position.y -= 8;
        }

        if (self.position.y < 0.0) {
            self.position.y = 0.0;
        }

        const screen_height = @as(f32, @floatFromInt(r.GetScreenHeight()));
        if (self.position.y + 80.0 > screen_height) {
            self.position.y = screen_height - 80.0;
        }
    }

    pub fn handle_powerup(self: *Player, ball: *Ball, sounds: *SoundDirectory) void {
        self.visual_offset *= 0.9;
        if (!self.has_powerup) return;
        if (!r.IsKeyDown(self.powerup_key)) return;

        self.has_powerup = false;
        const visualSelf = rm.Vector2Add(self.position, rm.Vector2 { .x = 0.0, .y = 40.0 });
        const dist = rm.Vector2Distance(visualSelf, ball.position);
        if (dist < 240.0) {
            const between = rm.Vector2Subtract(ball.position, visualSelf);
            const betweenNormalized = rm.Vector2Normalize(between);
            const betweenScaled = rm.Vector2Scale(betweenNormalized, ((240.0 - dist) / 80.0) * rm.Vector2Length(ball.velocity));
            ball.velocity = betweenScaled;
            ball.has_power = true;
        }
        r.PlaySound(sounds.powerUp);
        self.visual_offset = 40.0 * floatSign(ball.velocity.x);

    }

    pub fn render(self: *Player) void {
        var colour = r.WHITE;
        if (self.has_powerup) {
            colour = r.YELLOW;
        }
        r.DrawRectangle(@intFromFloat(self.position.x - 10 + self.visual_offset), @intFromFloat(self.position.y), 20, 80, colour);
    }
};

const SoundDirectory = struct {
    powerUp: r.Sound,
    ballHit: r.Sound,
    death: r.Sound,
};

pub fn main() !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("Pong -- made in Zig.\n", .{});
    r.InitWindow(800, 800, "Pong");
    r.InitAudioDevice();
    defer r.CloseAudioDevice();
    while (!r.IsAudioDeviceReady()) {}

    var sounds = SoundDirectory {
        .powerUp = r.LoadSoundFromWave(r.LoadWaveFromMemory(".wav", powerUp, powerUp.len)),
        .ballHit = r.LoadSoundFromWave(r.LoadWaveFromMemory(".wav", ballHit, ballHit.len)),
        .death = r.LoadSoundFromWave(r.LoadWaveFromMemory(".wav", death, death.len)),
    };
    defer r.UnloadSound(sounds.powerUp);
    defer r.UnloadSound(sounds.ballHit);
    defer r.UnloadSound(sounds.death);

    var playerOne = Player.init(30, r.KEY_W, r.KEY_S, r.KEY_D, false);
    var playerTwo = Player.init(@floatFromInt(r.GetScreenWidth() - 30), r.KEY_UP, r.KEY_DOWN, r.KEY_LEFT, false);

    const players = &[_] *Player {&playerOne, &playerTwo};

    r.SetTargetFPS(60);
    defer r.CloseWindow();

    var ball = Ball {
        .position = rm.Vector2 {
            .x = @as(f32, @floatFromInt(r.GetScreenWidth())) / @as(f32, 2.0),
            .y = @as(f32, @floatFromInt(r.GetScreenHeight())) / @as(f32, 2.0),
        },
        .velocity = rm.Vector2 {
            .x = -3.0,
            .y = -3.0,
        },
        .has_power = false,
    };

    while (!r.WindowShouldClose()) {
        r.BeginDrawing();
        defer r.EndDrawing();

        r.ClearBackground(r.BLACK);
        const centre = @divFloor(r.GetScreenWidth(), 2);

        // Create buffer for score card
        var buffer: [64]u8 = undefined;
        var buf_alloc = std.heap.FixedBufferAllocator.init(&buffer);
        const alloc = buf_alloc.allocator();

        var count: u32 = 0;
        for (players) |player| {
            count += 1;
            _ = try std.fmt.allocPrint(alloc, "{}", .{player.score});
            if (count != players.len) {
                const byte = try alloc.create(u8);
                byte.* = ':';
            }
        }
        const byte = try alloc.create(u8);
        byte.* = 0;

        drawTextCentered(@as([*c]u8, &buffer), centre, 20, 64, r.WHITE);

        const segment_size: i32 = 25;
        const segments = @divFloor(r.GetScreenHeight(), segment_size);

        var i: i32 = 4;
        while (i <= segments) {
            const should_draw = @mod(i, 2) == 0;
            if (should_draw) {
                r.DrawLineEx(r.Vector2{ .x = @floatFromInt(centre), .y = @floatFromInt(i * segment_size) }, r.Vector2{ .x = @floatFromInt(centre), .y = @floatFromInt((i + 1) * segment_size) }, 5, r.WHITE);
            }
            i += 1;
        }

        for (players) |player| {
            player.handle_inputs();
            player.handle_powerup(&ball, &sounds);
        }

        ball.handle_movement(players, &sounds);

        for (players) |player| {
            player.render();
        }

        ball.render();
    }

    try bw.flush(); // don't forget to flush!
}

fn drawTextCentered(text: [*c]u8, x: i32, y: i32, size: i32, color: r.Color) void {
    const sz = r.MeasureText(text, size);
    r.DrawText(text, x - @divFloor(sz, 2), y, size, color);
}
