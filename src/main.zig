//! Draws a light simulation to the terminal (you can zoom out for higher resolution)!
const std = @import("std");

const Point = @Vector(2, f32);

fn getDistance(v: Point, w: Point) f32 {
    const diff = v - w;
    return @sqrt(@reduce(.Add, diff * diff));
}

const State = struct {
    emitter: Body,
    receiver: Body,
    pub fn next(self: *State, speed: f32) f32 {
        var new_speed = speed;
        if (self.emitter.p[0] >= 1.0) {
            new_speed = -@abs(speed);
        } else if (self.emitter.p[0] <= 0.0) {
            new_speed = @abs(speed);
        }
        self.emitter.p[0] += new_speed;
        self.receiver.p[0] -= new_speed;
        return new_speed;
    }
};

const Screen = struct {
    rows: i32,
    cols: i32,
    pub fn init(stdout_file: std.Io.File) !Screen {
        return getTerminalSizePosix(stdout_file);
    }
    pub fn get_point(self: *const Screen, x: i32, y: i32) Point {
        return .{
            @as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(self.cols)),
            @as(f32, @floatFromInt(y)) / @as(f32, @floatFromInt(2 * self.rows)),
        };
    }
};

const Body = struct {
    p: Point,
    r: f32,
    i: f32,
};

fn getTerminalSizePosix(out_file: std.Io.File) !Screen {
    var winsize: std.posix.winsize = .{
        .row = 0,
        .col = 0,
        .xpixel = 0,
        .ypixel = 0,
    };
    const err = std.posix.system.ioctl(out_file.handle, std.posix.T.IOCGWINSZ, @intFromPtr(&winsize));
    if (std.posix.errno(err) != .SUCCESS) {
        return error.TerminalSizeUnavailable;
    }
    return .{
        .rows = winsize.row,
        .cols = winsize.col,
    };
}

fn absDiffUnsigned(x: f32, y: f32) f32 {
    return if (x > y) x - y else y - x;
}

fn calculateFalloff(distance: f32, intensity: f32) i32 {
    return @as(i32, @trunc(@max(0.0, @min(1.0, (1 - distance / intensity))) * 255.0));
}

fn isInShadow(point: Point, emitter: Body, receiver: Body) bool {
    const ray_dir = emitter.p - point;
    const to_receiver = receiver.p - point;
    const ray_len_sq = @reduce(.Add, ray_dir * ray_dir);
    if (ray_len_sq == 0.0) return false; // Avoid division by zero if point is on emitter
    const dot = @reduce(.Add, to_receiver * ray_dir);
    var t = dot / ray_len_sq;
    if (t < 0.0) t = 0.0;
    if (t > 1.0) t = 1.0;
    const closest_point = point + (@as(Point, @splat(t)) * ray_dir);
    const dist_vec = receiver.p - closest_point;
    const dist_sq = @reduce(.Add, dist_vec * dist_vec);
    return dist_sq < (receiver.r * receiver.r);
}

fn calculateIntensity(point: Point, state: State) i32 {
    if (getDistance(point, state.receiver.p) <= state.receiver.r) {
        return 0;
    }
    if (getDistance(point, state.emitter.p) <= state.emitter.r) {
        return 255;
    }
    const shadow_effect: f32 = if (isInShadow(point, state.emitter, state.receiver)) 1.1 else 1;
    return calculateFalloff(shadow_effect * getDistance(point, state.emitter.p), state.emitter.i);
}

/// Gets the dimension of the terminal, and uses the `state` to calculate the intensity, drawing the character to Io.
fn drawFrame(stdout: *std.Io.Writer, screen: Screen, state: State) !void {
    try stdout.print("\x1b[H", .{});
    var y: i32 = 0;
    while (y < screen.rows) : (y += 1) {
        if (y != 0) {
            try stdout.print("\n", .{});
        }
        var x: i32 = 0;
        while (x < screen.cols) : (x += 1) {
            const top_point = screen.get_point(x, 2 * y);
            const bottom_point = screen.get_point(x, (2 * y) + 1);
            const top_intensity = calculateIntensity(top_point, state);
            const bottom_intensity = calculateIntensity(bottom_point, state);
            try stdout.print("\x1b[38;2;{d};{d};{d}m\x1b[48;2;{d};{d};{d}m▀\x1b[0m", .{
                top_intensity,
                top_intensity,
                top_intensity,
                bottom_intensity,
                bottom_intensity,
                bottom_intensity,
            });
        }
    }
    try stdout.flush();
}

pub fn main(init: std.process.Init) !void {
    // variable setup
    const io = init.io;
    var stdout_buf: [4096]u8 = undefined;
    var stdout_file = std.Io.File.stdout();
    var stdout_writer = stdout_file.writer(io, &stdout_buf);
    const stdout = &stdout_writer.interface;
    try stdout.print("\x1b[?1049h\x1b[?25l\x1b[?7l", .{});
    try stdout.flush();
    // state setup
    const target_frame_time_ns = (1000 * std.time.ns_per_ms) / 60;
    var state = State{ .emitter = Body{ .p = .{ 0, 0.5 }, .r = 0.01, .i = 0.5 }, .receiver = Body{ .p = .{ 1, 0.3 }, .r = 0.01, .i = 0 } };
    var speed: f32 = 0.01;
    // play loop
    while (true) {
        const start_time = std.Io.Timestamp.now(io, .awake);
        speed = state.next(speed);
        const screen = try Screen.init(stdout_file);
        try drawFrame(stdout, screen, state);
        // wait to cap frame rate
        const elapsed_ns = start_time.untilNow(io, .awake).toNanoseconds();
        if (elapsed_ns < target_frame_time_ns) {
            try io.sleep(std.Io.Duration.fromNanoseconds(target_frame_time_ns - elapsed_ns), .awake);
        }
    }
}
