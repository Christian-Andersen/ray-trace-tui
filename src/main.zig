const std = @import("std");

const Point = @Vector(2, f32);

fn getDistance(v: Point, w: Point) f32 {
    const diff = v - w;
    return @sqrt(@reduce(.Add, diff * diff));
}

const Body = struct {
    p: Point,
    r: f32,
    i: f32,
};

fn getTerminalSizePosix(out_file: std.Io.File) !struct { rows: i32, cols: i32 } {
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

fn calculateIntensity(point: Point, emitter: Body, receiver: Body) i32 {
    if (getDistance(point, receiver.p) <= receiver.r) {
        return 0;
    }
    if (getDistance(point, emitter.p) <= emitter.r) {
        return 255;
    }
    const shadow_effect: f32 = if (isInShadow(point, emitter, receiver)) 1.1 else 1;
    return calculateFalloff(shadow_effect * getDistance(point, emitter.p), emitter.i);
}

fn drawFrame(stdout_file: std.Io.File, stdout: *std.Io.Writer, emitter: Body, receiver: Body) !void {
    const size_result = getTerminalSizePosix(stdout_file);
    const rows = if (size_result) |s| s.rows else |_| 32;
    const cols = if (size_result) |s| s.cols else |_| 64;
    try stdout.print("\x1b[H", .{});
    var y: i32 = 0;
    while (y < rows) : (y += 1) {
        if (y != 0) {
            try stdout.print("\n", .{});
        }
        var x: i32 = 0;
        while (x < cols) : (x += 1) {
            const top_point = .{
                @as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(cols)),
                @as(f32, @floatFromInt(2 * y)) / @as(f32, @floatFromInt(2 * rows)),
            };
            const top_intensity = calculateIntensity(top_point, emitter, receiver);
            const bottom_point = .{
                @as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(cols)),
                @as(f32, @floatFromInt((2 * y) + 1)) / @as(f32, @floatFromInt(2 * rows)),
            };
            const bottom_intensity = calculateIntensity(bottom_point, emitter, receiver);
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
    const io = init.io;
    var stdout_buf: [4096]u8 = undefined;
    var stdout_file = std.Io.File.stdout();
    var stdout_writer = stdout_file.writer(io, &stdout_buf);
    const stdout = &stdout_writer.interface;
    try stdout.print("\x1b[?1049h\x1b[?25l\x1b[?7l", .{});
    try stdout.flush();
    const target_frame_time_ns = (1000 * std.time.ns_per_ms) / 60;
    var emitter = Body{ .p = .{ 0, 0.5 }, .r = 0.01, .i = 0.5 };
    var receiver = Body{ .p = .{ 1, 0.3 }, .r = 0.01, .i = 0 };
    var speed: f32 = 0.01;
    while (true) {
        if (emitter.p[0] >= 1.0) {
            speed = -@abs(speed);
        } else if (emitter.p[0] <= 0.0) {
            speed = @abs(speed);
        }
        emitter.p[0] += speed;
        receiver.p[0] -= speed;
        const start_time = std.Io.Timestamp.now(io, .awake);
        try drawFrame(stdout_file, stdout, emitter, receiver);
        const elapsed_ns = start_time.untilNow(io, .awake).toNanoseconds();
        if (elapsed_ns < target_frame_time_ns) {
            const sleep_time_ns = target_frame_time_ns - elapsed_ns;
            const sleep_duration = std.Io.Duration.fromNanoseconds(sleep_time_ns);
            try io.sleep(sleep_duration, .awake);
        }
    }
}
