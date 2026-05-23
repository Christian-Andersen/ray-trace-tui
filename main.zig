const std = @import("std");

const Body = struct {
    x: usize,
    y: usize,
    r: usize,
    i: f32,
};

pub fn getTerminalSizePosix(out_file: std.Io.File) !struct { rows: u16, cols: u16 } {
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

fn absDiffUnsigned(x: usize, y: usize) usize {
    return if (x > y) x - y else y - x;
}

fn calculateDistance(x: usize, y: usize, sun: Body) f32 {
    const x_dist: f32 = @floatFromInt(absDiffUnsigned(x, sun.x));
    const y_dist: f32 = @floatFromInt(absDiffUnsigned(y, sun.y));
    return @sqrt(x_dist * x_dist + y_dist * y_dist);
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var stdout_buf: [4096]u8 = undefined;
    var stdout_file = std.Io.File.stdout();
    var stdout_writer = stdout_file.writer(io, &stdout_buf);
    const stdout = &stdout_writer.interface;
    const target_frame_time_ns = (1000 * std.time.ns_per_ms) / 60;
    const size_result = getTerminalSizePosix(stdout_file);
    const rows = if (size_result) |s| s.rows else |_| 32;
    const cols = if (size_result) |s| s.cols else |_| 64;
    for (0..cols) |sun_x| {
        const start_time = std.Io.Timestamp.now(io, .awake);
        const sun = Body{ .x = sun_x, .y = rows / 2, .r = 1, .i = 30 };
        try stdout.print("\x1B[2J\x1B[H", .{});
        for (0..rows) |y| {
            for (0..cols) |x| {
                const v: f32 = 1 - (calculateDistance(x, y, sun) / sun.i);
                const intensity: usize = @as(usize, @intFromFloat(@max(0.0, @min(1.0, v)) * 255.0));
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
