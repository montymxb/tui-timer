# Terminal Timer & Stopwatch

A simple terminal-based stopwatch and countdown timer built with Go and Bubble Tea. Predominantly to provide a way to set timers & use a stopwatch without moving out of the context of the terminal.

## Features

- **Stopwatch Mode**: Track elapsed time with centisecond precision
- **Timer Mode**: Countdown timer with visual progress bar
- **Beautiful UI**: Clean, centered design with dynamic colors
- **Terminal Bell**: Audible notification when timer completes
- **Responsive**: Adapts to any terminal size
- **Simple Controls**: Keyboard shortcuts for all actions

## Installation

```bash
# Clone or download the files
# Then build:
go build -o timer

# Or install directly:
go install
```

## Usage

### Stopwatch

```bash
# Start stopwatch immediately
timer --stopwatch
timer --start
timer -s

# Start in paused mode (press space to start)
timer
```

### Countdown Timer

```bash
# 5 minute timer
timer 5m

# 1 hour 30 minute timer
timer 1h30m

# 90 second timer
timer 90s

# 2 hour 15 minute 30 second timer
timer 2h15m30s
```

## Controls

- **Space**: Pause/Resume
- **R**: Reset
- **Q** or **Ctrl+C**: Quit

## Features

### Stopwatch

- Large, easy-to-read time display (HH:MM:SS.CS)
- Cyan/blue color theme
- Shows running/paused state
- Centisecond precision

### Timer

- Large countdown display (HH:MM:SS)
- Visual progress bar showing time remaining
- Percentage indicator
- Dynamic colors:
  - Green: > 50% time remaining
  - Yellow: 20-50% time remaining
  - Orange: < 20% time remaining
  - Red: Time's up!
- Terminal bell notification when complete

## Requirements

- Go 1.21 or later
- Terminal with color support

## Dependencies

- [Bubble Tea](https://github.com/charmbracelet/bubbletea) - TUI framework
- [Lipgloss](https://github.com/charmbracelet/lipgloss) - Terminal styling

## License

MIT

