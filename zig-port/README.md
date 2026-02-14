# TUI Timer - Zig Port

This is a Zig port of the tui-timer project, originally written in Go. It provides the same functionality as the original: a terminal-based stopwatch and countdown timer with a clean TUI interface.

## Features

- **Stopwatch Mode**: Track elapsed time with centisecond precision
- **Timer Mode**: Countdown timer with visual progress bar
- **Beautiful UI**: Clean, centered design with dynamic colors using ANSI escape codes
- **Terminal Bell**: Audible notification when timer completes
- **Responsive**: Adapts to terminal size
- **Simple Controls**: Keyboard shortcuts for all actions

## Requirements

- Zig 0.15.2 (tested with this version; may work with 0.13+)
- Terminal with color support
- Linux or macOS (uses POSIX terminal APIs)

## Building

```bash
cd zig-port
zig build
```

The compiled binary will be located at `zig-out/bin/timer`.

## Installation

After building, you can copy the binary to your PATH:

```bash
sudo cp zig-out/bin/timer /usr/local/bin/
```

## Usage

### Stopwatch

```bash
# Start stopwatch immediately
./zig-out/bin/timer --stopwatch
./zig-out/bin/timer --start
./zig-out/bin/timer -s

# Start in paused mode (press space to start)
./zig-out/bin/timer
```

### Countdown Timer

```bash
# 5 minute timer
./zig-out/bin/timer 5m

# 1 hour 30 minute timer
./zig-out/bin/timer 1h30m

# 90 second timer
./zig-out/bin/timer 90s

# 2 hour 15 minute 30 second timer
./zig-out/bin/timer 2h15m30s
```

## Controls

- **Space**: Pause/Resume
- **R**: Reset
- **Q** or **Esc** or **Ctrl+C**: Quit

## Implementation Details

This port uses:
- Zig's standard library for terminal manipulation
- Raw terminal mode for non-blocking keyboard input (termios)
- ANSI escape codes for colors and positioning
- Direct POSIX system calls for terminal size detection (ioctl)
- i128 for nanosecond timestamp precision

The implementation maintains the same architecture as the Go version:
- `Mode` enum (stopwatch/timer)
- `State` enum (running/paused/finished)
- `Model` struct containing application state
- Tick-based update loop (10ms intervals)

## Differences from Go Version

- Uses ANSI escape codes directly instead of a TUI framework like Bubble Tea
- Terminal manipulation uses POSIX APIs (tcgetattr/tcsetattr)
- Simpler rendering but maintains the same visual style and functionality
- Linux/macOS compatible (the Go version is cross-platform including Windows)

## License

MIT (same as the original project)
