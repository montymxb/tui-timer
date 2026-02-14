const std = @import("std");
const time = std.time;

const Mode = enum {
    stopwatch,
    timer,
};

const State = enum {
    running,
    paused,
    finished,
};

const Model = struct {
    mode: Mode,
    state: State,
    duration: i128, // nanoseconds
    target_time: i128, // nanoseconds
    last_tick: i128, // nanoseconds
    width: u16,
    height: u16,
    needs_render: bool,
};

// terminal state for cleanup
var original_termios: ?std.posix.termios = null;

// ANSI escape codes
const ANSI = struct {
    const clear_screen = "\x1b[2J";
    const hide_cursor = "\x1b[?25l";
    const show_cursor = "\x1b[?25h";
    const alt_screen_enter = "\x1b[?1049h";
    const alt_screen_exit = "\x1b[?1049l";
    const reset = "\x1b[0m";
    const bold = "\x1b[1m";
    const move_home = "\x1b[H";

    fn color(comptime code: []const u8) []const u8 {
        return "\x1b[38;5;" ++ code ++ "m";
    }
};

// enters raw mode for terminal
fn enterRawMode() !void {
    if (original_termios != null) return;

    const stdin_fd = std.posix.STDIN_FILENO;
    var termios = try std.posix.tcgetattr(stdin_fd);
    original_termios = termios;

    // disable canonical mode and echo
    termios.lflag.ECHO = false;
    termios.lflag.ICANON = false;
    termios.lflag.ISIG = false;
    termios.lflag.IEXTEN = false;

    termios.iflag.IXON = false;
    termios.iflag.ICRNL = false;
    termios.iflag.BRKINT = false;
    termios.iflag.INPCK = false;
    termios.iflag.ISTRIP = false;

    termios.oflag.OPOST = false;
    termios.cflag.CSIZE = .CS8;

    // set read timeout
    termios.cc[@intFromEnum(std.posix.V.TIME)] = 0;
    termios.cc[@intFromEnum(std.posix.V.MIN)] = 0;

    try std.posix.tcsetattr(stdin_fd, .FLUSH, termios);
}

// exits raw mode
fn exitRawMode() void {
    if (original_termios) |term| {
        const stdin_fd = std.posix.STDIN_FILENO;
        std.posix.tcsetattr(stdin_fd, .FLUSH, term) catch {};
        original_termios = null;
    }
}

// gets terminal size
fn getTerminalSize() !struct { width: u16, height: u16 } {
    var winsize: std.posix.winsize = undefined;
    const result = std.c.ioctl(std.posix.STDOUT_FILENO, std.posix.T.IOCGWINSZ, @intFromPtr(&winsize));
    if (result != 0) {
        return error.IoctlFailed;
    }
    return .{ .width = winsize.col, .height = winsize.row };
}

// formats duration to string
fn formatDuration(allocator: std.mem.Allocator, duration: i128, show_millis: bool) ![]u8 {
    // round to 10ms (centiseconds) to match Go version
    const rounded = @divTrunc(duration + (5 * time.ns_per_ms), 10 * time.ns_per_ms) * (10 * time.ns_per_ms);
    var d = @max(0, rounded); // ensure non-negative
    const hours = @divTrunc(d, time.ns_per_hour);
    d -= hours * time.ns_per_hour;
    const minutes = @divTrunc(d, time.ns_per_min);
    d -= minutes * time.ns_per_min;
    const seconds = @divTrunc(d, time.ns_per_s);
    d -= seconds * time.ns_per_s;
    const centiseconds = @divTrunc(d, 10 * time.ns_per_ms);

    if (show_millis) {
        return try std.fmt.allocPrint(allocator, "{d:0>2}:{d:0>2}:{d:0>2}.{d:0>2}", .{
            hours,
            minutes,
            seconds,
            centiseconds,
        });
    } else {
        return try std.fmt.allocPrint(allocator, "{d:0>2}:{d:0>2}:{d:0>2}", .{
            hours,
            minutes,
            seconds,
        });
    }
}

// parses duration from string (e.g., "5m", "1h30m", "90s")
fn parseDuration(input: []const u8) !i128 {
    var total: i128 = 0;
    var i: usize = 0;
    var num: i128 = 0;

    while (i < input.len) : (i += 1) {
        const c = input[i];
        if (c >= '0' and c <= '9') {
            num = num * 10 + (c - '0');
        } else if (c == 'h') {
            total += num * time.ns_per_hour;
            num = 0;
        } else if (c == 'm') {
            total += num * time.ns_per_min;
            num = 0;
        } else if (c == 's') {
            total += num * time.ns_per_s;
            num = 0;
        }
    }

    if (total == 0) {
        return error.InvalidDuration;
    }

    return total;
}

// helper function to write formatted text to stdout
fn writeFmt(stdout: std.fs.File, allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !void {
    const text = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(text);
    _ = try stdout.write(text);
}

// renders stopwatch view
fn renderStopwatch(stdout: std.fs.File, model: *const Model, allocator: std.mem.Allocator) !void {
    const color_code = comptime ANSI.color("86"); // cyan

    // format time
    const time_str = try formatDuration(allocator, model.duration, true);
    defer allocator.free(time_str);

    // state indicator (padded to consistent visual width)
    const state_str = if (model.state == .running) "▶ RUNNING " else "⏸ PAUSED  ";

    // calculate center position
    const center_row = model.height / 2;
    const center_col = model.width / 2;

    // render title (centered)
    const title = "STOPWATCH";
    const title_col = if (center_col > title.len / 2) center_col - @as(u16, @intCast(title.len / 2)) else 1;
    try writeFmt(stdout, allocator, "{s}\x1b[1;{d}H{s}{s}{s}{s}", .{
        ANSI.move_home,
        title_col,
        ANSI.bold,
        color_code,
        title,
        ANSI.reset,
    });

    // render box with content
    const box_width = 30;
    const start_col = if (center_col > box_width / 2) center_col - box_width / 2 else 1;

    // move to center and render box
    try writeFmt(stdout, allocator, "\x1b[{d};{d}H╭{s}╮", .{ center_row - 3, start_col, "─" ** 28 });
    try writeFmt(stdout, allocator, "\x1b[{d};{d}H│{s: ^28}│", .{ center_row - 2, start_col, "" });
    try writeFmt(stdout, allocator, "\x1b[{d};{d}H│{s}{s}{s: ^28}{s}│", .{ center_row - 1, start_col, ANSI.bold, color_code, state_str, ANSI.reset });
    try writeFmt(stdout, allocator, "\x1b[{d};{d}H│{s: ^28}│", .{ center_row, start_col, "" });
    try writeFmt(stdout, allocator, "\x1b[{d};{d}H│{s}{s}{s: ^28}{s}│", .{ center_row + 1, start_col, ANSI.bold, color_code, time_str, ANSI.reset });
    try writeFmt(stdout, allocator, "\x1b[{d};{d}H│{s: ^28}│", .{ center_row + 2, start_col, "" });
    try writeFmt(stdout, allocator, "\x1b[{d};{d}H╰{s}╯", .{ center_row + 3, start_col, "─" ** 28 });

    // render help text at bottom (centered)
    const help_text = "space: pause/resume • r: reset • q: quit";
    const help_col = if (center_col > help_text.len / 2) center_col - @as(u16, @intCast(help_text.len / 2)) else 1;
    try writeFmt(stdout, allocator, "\x1b[{d};{d}H{s}{s}{s}", .{
        model.height - 2,
        help_col,
        ANSI.color("241"),
        help_text,
        ANSI.reset,
    });
}

// renders timer view
fn renderTimer(stdout: std.fs.File, model: *const Model, allocator: std.mem.Allocator) !void {
    // dynamic colors based on time remaining
    const color_code = if (model.state == .finished)
        ANSI.color("196") // red
    else blk: {
        const percentage = @as(f64, @floatFromInt(model.duration)) / @as(f64, @floatFromInt(model.target_time));
        if (percentage > 0.5) {
            break :blk ANSI.color("82"); // green
        } else if (percentage > 0.2) {
            break :blk ANSI.color("226"); // yellow
        } else {
            break :blk ANSI.color("208"); // orange
        }
    };

    // format time
    const time_str = try formatDuration(allocator, model.duration, false);
    defer allocator.free(time_str);

    // state indicator (padded to consistent visual width)
    const state_str = if (model.state == .finished)
        "🔔 TIME'S UP!"
    else if (model.state == .running)
        "▶ RUNNING   "
    else
        "⏸ PAUSED    ";

    // calculate center position
    const center_row = model.height / 2;
    const center_col = model.width / 2;

    // render title (centered)
    const title = "COUNTDOWN TIMER";
    const title_col = if (center_col > title.len / 2) center_col - @as(u16, @intCast(title.len / 2)) else 1;
    try writeFmt(stdout, allocator, "{s}\x1b[1;{d}H{s}{s}{s}{s}", .{
        ANSI.move_home,
        title_col,
        ANSI.bold,
        color_code,
        title,
        ANSI.reset,
    });

    // render box with content
    const box_width = 30;
    const start_col = if (center_col > box_width / 2) center_col - box_width / 2 else 1;

    // move to center and render box
    try writeFmt(stdout, allocator, "\x1b[{d};{d}H╭{s}╮", .{ center_row - 3, start_col, "─" ** 28 });
    try writeFmt(stdout, allocator, "\x1b[{d};{d}H│{s: ^28}│", .{ center_row - 2, start_col, "" });
    try writeFmt(stdout, allocator, "\x1b[{d};{d}H│{s}{s}{s: ^28}{s}│", .{ center_row - 1, start_col, ANSI.bold, color_code, state_str, ANSI.reset });
    try writeFmt(stdout, allocator, "\x1b[{d};{d}H│{s: ^28}│", .{ center_row, start_col, "" });
    try writeFmt(stdout, allocator, "\x1b[{d};{d}H│{s}{s}{s: ^28}{s}│", .{ center_row + 1, start_col, ANSI.bold, color_code, time_str, ANSI.reset });
    try writeFmt(stdout, allocator, "\x1b[{d};{d}H│{s: ^28}│", .{ center_row + 2, start_col, "" });
    try writeFmt(stdout, allocator, "\x1b[{d};{d}H╰{s}╯", .{ center_row + 3, start_col, "─" ** 28 });

    // render progress bar
    const percentage = @as(f64, @floatFromInt(model.duration)) / @as(f64, @floatFromInt(model.target_time));
    const bar_width = 40;
    const filled = @as(usize, @intFromFloat(@max(0, @min(percentage * @as(f64, @floatFromInt(bar_width)), @as(f64, @floatFromInt(bar_width))))));

    // build filled and empty parts
    const filled_part = try allocator.alloc(u8, filled * 3); // "█" is 3 bytes in UTF-8
    defer allocator.free(filled_part);
    var pos: usize = 0;
    for (0..filled) |_| {
        @memcpy(filled_part[pos..pos+3], "█");
        pos += 3;
    }

    const empty_part = try allocator.alloc(u8, (bar_width - filled) * 3); // "░" is 3 bytes in UTF-8
    defer allocator.free(empty_part);
    pos = 0;
    for (0..(bar_width - filled)) |_| {
        @memcpy(empty_part[pos..pos+3], "░");
        pos += 3;
    }

    const bar_str = try std.fmt.allocPrint(allocator, "{s}{s}{s} {d:.0}%{s}", .{
        color_code,
        filled_part,
        empty_part,
        percentage * 100,
        ANSI.reset,
    });
    defer allocator.free(bar_str);

    try writeFmt(stdout, allocator, "\x1b[{d};{d}H{s}", .{
        center_row + 5,
        if (center_col > bar_width / 2) center_col - bar_width / 2 else 1,
        bar_str,
    });

    // render help text at bottom (centered)
    const help_text = "space: pause/resume • r: reset • q: quit";
    const help_col = if (center_col > help_text.len / 2) center_col - @as(u16, @intCast(help_text.len / 2)) else 1;
    try writeFmt(stdout, allocator, "\x1b[{d};{d}H{s}{s}{s}", .{
        model.height - 2,
        help_col,
        ANSI.color("241"),
        help_text,
        ANSI.reset,
    });
}

// renders the current view
fn render(model: *const Model, allocator: std.mem.Allocator) !void {
    const stdout = std.fs.File{ .handle = std.posix.STDOUT_FILENO };

    // clear screen and move to home
    _ = try stdout.write(ANSI.clear_screen);
    _ = try stdout.write(ANSI.move_home);

    if (model.mode == .stopwatch) {
        try renderStopwatch(stdout, model, allocator);
    } else {
        try renderTimer(stdout, model, allocator);
    }
}

// handles keyboard input
fn handleInput(model: *Model) !bool {
    const stdin = std.fs.File{ .handle = std.posix.STDIN_FILENO };
    var buf: [3]u8 = undefined;
    const n = stdin.read(&buf) catch 0;

    if (n == 0) return true;

    // check for quit keys
    if (buf[0] == 'q' or buf[0] == 27) { // 'q' or ESC
        return false;
    } else if (buf[0] == 3) { // Ctrl+C
        return false;
    } else if (buf[0] == ' ') { // space
        if (model.state != .finished) {
            if (model.state == .running) {
                model.state = .paused;
                model.needs_render = true;
            } else {
                model.state = .running;
                model.last_tick = time.nanoTimestamp();
                model.needs_render = true;
            }
        }
    } else if (buf[0] == 'r') { // reset
        model.duration = 0;
        model.state = .paused;
        model.needs_render = true;
    }

    return true;
}

// updates model state
fn update(model: *Model) void {
    if (model.state != .running) return;

    const now = time.nanoTimestamp();
    const elapsed = now - model.last_tick;
    model.last_tick = now;

    if (model.mode == .stopwatch) {
        model.duration += elapsed;
        model.needs_render = true;
    } else {
        model.duration -= elapsed;
        model.needs_render = true;
        if (model.duration <= 0) {
            model.duration = 0;
            model.state = .finished;
            // terminal bell
            const stdout = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
            _ = stdout.write("\x07") catch {};
        }
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.fs.File{ .handle = std.posix.STDOUT_FILENO };

    // parse command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var model = Model{
        .mode = .stopwatch,
        .state = .paused,
        .duration = 0,
        .target_time = 0,
        .last_tick = 0,
        .width = 80,
        .height = 24,
        .needs_render = true,
    };

    if (args.len > 1) {
        const arg = args[1];

        // check for stopwatch mode
        if (std.mem.eql(u8, arg, "--stopwatch") or
            std.mem.eql(u8, arg, "--start") or
            std.mem.eql(u8, arg, "-s"))
        {
            model.mode = .stopwatch;
            model.state = .running;
            model.last_tick = time.nanoTimestamp();
        } else {
            // try to parse as duration for timer mode
            const duration = parseDuration(arg) catch |err| {
                const msg = try std.fmt.allocPrint(allocator, "Error: {}\n\nUsage:\n  timer                 Start in interactive mode\n  timer --stopwatch     Start stopwatch\n  timer --start         Start stopwatch (alias)\n  timer 5m              Start 5-minute countdown\n  timer 1h30m           Start 1h30m countdown\n  timer 90s             Start 90-second countdown\n", .{err});
                defer allocator.free(msg);
                _ = try stdout.write(msg);
                return;
            };

            model.mode = .timer;
            model.duration = duration;
            model.target_time = duration;
            model.state = .running;
            model.last_tick = time.nanoTimestamp();
        }
    }

    // enter raw mode and alt screen
    try enterRawMode();
    defer exitRawMode();

    _ = try stdout.write(ANSI.alt_screen_enter);
    _ = try stdout.write(ANSI.hide_cursor);
    defer {
        _ = stdout.write(ANSI.show_cursor) catch {};
        _ = stdout.write(ANSI.alt_screen_exit) catch {};
    }

    // get initial terminal size
    const size = try getTerminalSize();
    model.width = size.width;
    model.height = size.height;

    // main loop
    while (true) {
        // update model
        update(&model);

        // render only when needed
        if (model.needs_render) {
            try render(&model, allocator);
            model.needs_render = false;
        }

        // handle input
        if (!try handleInput(&model)) {
            break;
        }

        // sleep for tick rate (10ms to match Go version)
        std.Thread.sleep(10 * time.ns_per_ms);
    }
}
