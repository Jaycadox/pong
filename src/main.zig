const std = @import("std");
const r = @cImport({
    @cInclude("raylib.h");
});
const rm = @cImport({
    @cInclude("raymath.h");
});


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
            // If I am colliding with player on the x-axis
            if (@abs(self.position.x - player.position.x) < 20.0) {
                var hit = false;
                // Check to see whether I am colliding with their side or bottom/top
                if (self.position.y > player.position.y and self.position.y < (player.position.y + 80)) {
                    hit = true;
                } else if (@abs(self.position.y - player.position.y) < 10.0 or @abs(self.position.y - (player.position.y + 80)) < 10.0) {
                    hit = true;
                }

                if (hit) {
                    // If so, flip movements and increase speed a little bit
                    r.PlaySound(sounds.ballHit);
                    self.velocity.x *= -1.1;
                    self.velocity.y *= 1.1;
                    // Teleport self to be at player's side (facing the other player), this is so we don't get double collisions on top/bottom
                    self.position.x = player.position.x + (20.0 * std.math.sign(self.velocity.x));

                    // Give boost/reduction of ball speed depending on motion of player
                    // Note: this is a really bad way of detecting this (doesn't account for bots)
                    if (r.IsKeyDown(player.down_key)) {
                        self.velocity.y += 1.0;
                    } else if (r.IsKeyDown(player.up_key)) {
                        self.velocity.y -= 1.0;
                    }

                    // If I have a powerup, and the player that I hit doesn't transfer my powerup to the player
                    if (self.has_power and !player.has_powerup) {
                        player.has_powerup = true;
                        self.has_power = false;
                    }
                }
            }
        }

        // Handle hitting top/bottom side of window
        {
            if (self.position.y < 10.0) {
                r.PlaySound(sounds.ballHit);
                self.velocity.y *= -1.0;
            }

            if (self.position.y >= (@as(f32, @floatFromInt(r.GetScreenHeight())) - 10.0)) {
                r.PlaySound(sounds.ballHit);
                self.velocity.y *= -1.0;
            }
        }

        // Handle hitting left/right side of the window (player missed)
        const screen_width = @as(f32, @floatFromInt(r.GetScreenWidth()));
        if (self.position.x < 0.0 or self.position.x > screen_width) {
            r.PlaySound(sounds.death);
            // Any player whose x position is more than half the screen away will be awarded a point
            // Any player closer will be awarded the powerup in the next round
            const half_screen = screen_width / 2.0;
            for (players) |player| {
                if (@abs(self.position.x - player.position.x) > half_screen) {
                    player.score += 1;
                    player.has_powerup = false;
                } else {
                    player.has_powerup = true;
                }
            }
            // Ball power does not persist between rounds
            self.has_power = false;

            // Reset ball velocity
            // TODO: perhaps randomize this?
            self.velocity = rm.Vector2 {
                .x = -3.0,
                .y = -3.0,
            };

            // Teleport ball to centre screen
            self.position = rm.Vector2 {
                .x = half_screen,
                .y = @as(f32, @floatFromInt(r.GetScreenHeight())) / @as(f32, 2.0),
            };
        }
    }
    pub fn render(self: *Ball) void {
        // Balls with active powerups are drawn yellow
        var colour = r.WHITE;
        if (self.has_power) {
            colour = r.YELLOW;
        }
        r.DrawCircle(@intFromFloat(self.position.x), @intFromFloat(self.position.y), 10.0, colour);
    }
};

const Action = enum {
    up,
    down,
    powerup,
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

    fn perform_action(self: *Player, action: Action, ball: *Ball, sounds: *SoundDirectory) void {
        if (action == Action.up or action == Action.down) {
            if (action == Action.up) {
                self.position.y -= 8;
            } else if (action == Action.down) {
                self.position.y += 8;
            }

            // Handle cases where player is attempting to go over or under play area by reverting their move
            if (self.position.y < 0.0) {
                self.position.y = 0.0;
            }
            const screen_height = @as(f32, @floatFromInt(r.GetScreenHeight()));
            if (self.position.y + 80.0 > screen_height) {
                self.position.y = screen_height - 80.0;
            }
        } else if (action == Action.powerup) {
            self.handle_powerup(ball, sounds);
        }

    }

    fn ai_tick(self: *Player, ball: *Ball, sounds: *SoundDirectory) void {
        const visualY = self.position.y + 40.0;

        // Check if the ball is somewhat far
        if (@abs(ball.position.y - visualY) >= 40.0) {
            // If it's above me, go up, if it's below me, go down
            if (ball.position.y > visualY) {
                self.perform_action(Action.down, ball, sounds);
            } else if (ball.position.y < visualY) {
                self.perform_action(Action.up, ball, sounds);
            }
        }

        // If I have a powerup and the ball is somewhat close to me, use it
        if (self.has_powerup and @abs(ball.position.x - self.position.x) <= 20.0) {
            self.perform_action(Action.powerup, ball, sounds);
        }
    }

    pub fn tick(self: *Player, ball: *Ball, sounds: *SoundDirectory) void {
        // When a bot/ai inputs a valid action, their AI state will be disabled

        if (r.IsKeyDown(self.down_key)) {
            self.perform_action(Action.down, ball, sounds);
            self.ai = false;
        }

        if (r.IsKeyDown(self.up_key)) {
            self.perform_action(Action.up, ball, sounds);
            self.ai = false;
        }

        if (r.IsKeyDown(self.powerup_key)) {
            self.perform_action(Action.powerup, ball, sounds);
            self.ai = false;
        }

        if (self.ai) {
            self.ai_tick(ball, sounds);
        }

        // The powerup specifies a visual offset to denote its operation, this needs to be decreased every subsequent frame
        self.visual_offset *= 0.9;
    }

    pub fn handle_powerup(self: *Player, ball: *Ball, sounds: *SoundDirectory) void {
        if (!self.has_powerup) return;

        self.has_powerup = false;
        // The coordinate of Player.position's y component is situated at the very top of the drawn rectangle
        // It should instead be moved down, because this is the true centre of the rectangle and should be
        // where the reflection is based
        const visualSelf = rm.Vector2Add(self.position, rm.Vector2 { .x = 0.0, .y = 40.0 });

        // Minimum threshold for distance between player and ball for powerup to activate
        const dist = rm.Vector2Distance(visualSelf, ball.position);
        if (dist < 240.0) {
            const between = rm.Vector2Subtract(ball.position, visualSelf);
            const betweenNormalized = rm.Vector2Normalize(between);
            const betweenScaled = rm.Vector2Scale(betweenNormalized, ((240.0 - dist) / 80.0) * rm.Vector2Length(ball.velocity));
            ball.velocity = betweenScaled;
            ball.has_power = true;
        }
        r.PlaySound(sounds.powerUp);

        // Shift visual offset either left or right depending on the current direction of the ball on the x-axis
        self.visual_offset = 40.0 * std.math.sign(ball.velocity.x);

    }

    pub fn render(self: *Player) void {
        // Players with an active powerup are drawn yellow
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

fn fillScoreCard(buffer: []u8, players:  []const* Player) !void {
    // Create an allocator pointing to the provided buffer
    var buf_alloc = std.heap.FixedBufferAllocator.init(buffer);
    const alloc = buf_alloc.allocator();

    var count: u32 = 0;
    // For every player, write (allocate) their score to the buffer, as well as a colon
    for (players) |player| {
        count += 1;
        if (player.ai) {
            _ = try std.fmt.allocPrint(alloc, "{} (Bot)", .{player.score});
        } else {
            _ = try std.fmt.allocPrint(alloc, "{}", .{player.score});
        }

        // Only allocate/write the colon if we aren't the last player
        if (count != players.len) {
            const byte = try alloc.create(u8);
            byte.* = ':';
        }
    }

    // Write a null-byte at the end so it's a proper C-string for Raylib
    const byte = try alloc.create(u8);
    byte.* = 0;
}

fn drawSegmentedLine(centre: i32) void {
    const segment_size: i32 = 25;
    // Calculate number of segments given the size of each segment and the height of the window
    const segments = @divFloor(r.GetScreenHeight(), segment_size);

    var i: i32 = 4;
    while (i <= segments) {
        // Alternate between drawing the segment and not drawing the segment, so the line isn't filled
        const should_draw = @mod(i, 2) == 0;
        if (should_draw) {
            r.DrawLineEx(r.Vector2{ .x = @floatFromInt(centre), .y = @floatFromInt(i * segment_size) }, r.Vector2{ .x = @floatFromInt(centre), .y = @floatFromInt((i + 1) * segment_size) }, 5, r.WHITE);
        }
        i += 1;
    }
}

pub fn main() !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("Pong -- made in Zig.\n", .{});
    try bw.flush();

    r.InitWindow(800, 800, "Pong");
    defer r.CloseWindow();
    r.SetTargetFPS(60);

    // Start audio device and wait for it to load
    r.InitAudioDevice();
    defer r.CloseAudioDevice();
    while (!r.IsAudioDeviceReady()) {}

    // Load/initialize sounds
    var sounds = SoundDirectory {
        .powerUp = r.LoadSoundFromWave(r.LoadWaveFromMemory(".wav", powerUp, powerUp.len)),
        .ballHit = r.LoadSoundFromWave(r.LoadWaveFromMemory(".wav", ballHit, ballHit.len)),
        .death = r.LoadSoundFromWave(r.LoadWaveFromMemory(".wav", death, death.len)),
    };
    defer r.UnloadSound(sounds.powerUp);
    defer r.UnloadSound(sounds.ballHit);
    defer r.UnloadSound(sounds.death);

    // Initialize players
    var playerOne = Player.init(30, r.KEY_W, r.KEY_S, r.KEY_D, false);
    var playerTwo = Player.init(@floatFromInt(r.GetScreenWidth() - 30), r.KEY_UP, r.KEY_DOWN, r.KEY_LEFT, true);
    const players = &[_] *Player {&playerOne, &playerTwo};

    // Initialize ball
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

        // Draw score card text at top of screen
        var buffer: [64]u8 = undefined;
        try fillScoreCard(&buffer, players);
        drawTextCentered(@as([*c]u8, &buffer), centre, 20, 64, r.WHITE);

        drawSegmentedLine(centre);

        // Tick and render each player and the ball
        for (players) |player| {
            player.tick(&ball, &sounds);
        }

        ball.handle_movement(players, &sounds);

        for (players) |player| {
            player.render();
        }

        ball.render();
    }

    try bw.flush();
}

fn drawTextCentered(text: [*c]u8, x: i32, y: i32, size: i32, color: r.Color) void {
    const sz = r.MeasureText(text, size);
    r.DrawText(text, x - @divFloor(sz, 2), y, size, color);
}
