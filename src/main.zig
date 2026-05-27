const std = @import("std");

const Point = @Vector(2, f32);

pub fn makePointFromInt(x: anytype, y: anytype) Point {
    const int_vec: @Vector(2, @TypeOf(x, y)) = .{ x, y };
    return @as(Point, @floatFromInt(int_vec));
}

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

fn isInShadow(point: Point, sun: Body, moon: Body) bool {
    const point_sun = sun.p - point;
    const point_moon = moon.p - point;
    const point_sun_length = @reduce(.Add, point_sun * point_sun);
    const t = @reduce(.Add, point_moon * point_sun) / point_sun_length;
    const projection = point + (@as(Point, @splat(t)) * (point_moon - point));
    const x_d = sun.p[0] - projection[0];
    const y_d = sun.p[1] - projection[1];
    const d = @sqrt(x_d * x_d + y_d * y_d);
    return d > moon.r;
}

fn calculateIntensity(point: Point, sun: Body, moon: Body) i32 {
    if (getDistance(point, moon.p) <= moon.r) {
        return 0;
    }
    if (getDistance(point, sun.p) <= sun.r) {
        return 255;
    }
    if (isInShadow(point, sun, moon)) {
        return calculateFalloff(getDistance(point, sun.p), sun.i);
    } else {
        return 25;
    }
    const distance: f32 = getDistance(point, sun.p);
    return calculateFalloff(distance, sun.i);
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var stdout_buf: [4096]u8 = undefined;
    var stdout_file = std.Io.File.stdout();
    var stdout_writer = stdout_file.writer(io, &stdout_buf);
    const stdout = &stdout_writer.interface;
    const target_frame_time_ns = (1000 * std.time.ns_per_ms) / 60;
    const size_result = getTerminalSizePosix(stdout_file);
    const rows = if (size_result) |s| s.rows - 1 else |_| 32;
    const cols = if (size_result) |s| s.cols else |_| 64;
    var sun = Body{ .p = makePointFromInt(0, @divTrunc(rows, 2)), .r = 0.0, .i = 80 };
    var moon = Body{ .p = makePointFromInt(cols, @divTrunc(rows, 3)), .r = 2.0, .i = 30 };
    while (sun.p[0] <= @as(f32, @floatFromInt(cols))) {
        sun.p[0] += 1;
        moon.p[0] -= 1;
        const start_time = std.Io.Timestamp.now(io, .awake);
        try stdout.print("\x1B[2J\x1B[H", .{});
        var y: i32 = 0;
        while (y < rows) : (y += 1) {
            var x: i32 = 0;
            while (x < cols) : (x += 1) {
                const point = makePointFromInt(x, y);
                const intensity = calculateIntensity(point, sun, moon);
                try stdout.print("\x1b[38;2;{d};{d};{d}m█\x1b[0m", .{
                    intensity,
                    intensity,
                    intensity,
                });
            }
            try stdout.print("\n", .{});
            try stdout.flush();
        }
        const elapsed_ns = start_time.untilNow(io, .awake).toNanoseconds();
        if (elapsed_ns < target_frame_time_ns) {
            const sleep_time_ns = target_frame_time_ns - elapsed_ns;
            const sleep_duration = std.Io.Duration.fromNanoseconds(sleep_time_ns);
            try io.sleep(sleep_duration, .awake);
        }
    }
}
