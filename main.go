package main

import (
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"runtime"
	"strconv"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

type mode int

const (
	modeStopwatch mode = iota
	modeTimer
)

type state int

const (
	stateRunning state = iota
	statePaused
	stateFinished
)

type model struct {
	mode         mode
	state        state
	duration     time.Duration
	targetTime   time.Duration
	lastTick     time.Time
	width        int
	height       int
}

type tickMsg time.Time
type chimeMsg struct{}

func tick() tea.Cmd {
	return tea.Tick(10*time.Millisecond, func(t time.Time) tea.Msg {
		return tickMsg(t)
	})
}

func chime() tea.Cmd {
	return tea.Tick(2*time.Second, func(t time.Time) tea.Msg {
		return chimeMsg{}
	})
}

func (m model) Init() tea.Cmd {
	return tea.Batch(tick(), tea.EnterAltScreen)
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		return m, nil

	case tea.KeyMsg:
		switch msg.String() {
		case "q", "ctrl+c", "esc":
			return m, tea.Quit
		case " ":
			if m.state == stateRunning || m.state == stateFinished {
				m.state = statePaused
				return m, nil
			} else {
				var cmd tea.Cmd
				if m.mode == modeTimer && m.duration <= 0 {
					m.state = stateFinished
					cmd = chime()
				} else {
					m.state = stateRunning
				}
				m.lastTick = time.Now()
				return m, cmd
			}
		case "r":
			if m.mode == modeStopwatch {
				m.duration = 0
			} else {
				m.duration = m.targetTime
			}
			m.state = statePaused
			return m, nil
		}

	case tickMsg:
		var cmd tea.Cmd
		if m.state == stateRunning || m.state == stateFinished {
			now := time.Time(msg)
			elapsed := now.Sub(m.lastTick)
			m.lastTick = now

			if m.mode == modeStopwatch {
				m.duration += elapsed
			} else {
				m.duration -= elapsed
				if m.duration <= 0 && m.state == stateRunning {
					m.state = stateFinished
					playSound()
					sendNotification("Timer", "Time's up!")
					cmd = chime()
				}
			}
		}
		return m, tea.Batch(tick(), cmd)

	case chimeMsg:
		if m.mode == modeTimer && m.state == stateFinished {
			playSound()
			return m, chime()
		}
		return m, nil
	}

	return m, nil
}

func (m model) View() string {
	var content string

	if m.mode == modeStopwatch {
		content = m.renderStopwatch()
	} else {
		content = m.renderTimer()
	}

	return content
}

func (m model) renderStopwatch() string {
	// Styles
	titleStyle := lipgloss.NewStyle().
		Foreground(lipgloss.Color("86")).
		Bold(true).
		Padding(1, 0)

	timeStyle := lipgloss.NewStyle().
		Foreground(lipgloss.Color("86")).
		Bold(true)

	boxStyle := lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(lipgloss.Color("86")).
		Padding(1, 4).
		Align(lipgloss.Center)

	helpStyle := lipgloss.NewStyle().
		Foreground(lipgloss.Color("241")).
		Padding(1, 0)

	// Format time
	timeStr := formatDuration(m.duration, true)

	// State indicator
	stateStr := "⏸ PAUSED"
	if m.state == stateRunning {
		stateStr = "▶ RUNNING"
	}

	stateStyle := lipgloss.NewStyle().
		Foreground(lipgloss.Color("86")).
		Padding(0, 0, 1, 0)

	// Build content
	title := titleStyle.Render("STOPWATCH")
	stateDisplay := stateStyle.Render(stateStr)
	timeDisplay := timeStyle.Render(timeStr)
	box := boxStyle.Render(lipgloss.JoinVertical(lipgloss.Center, stateDisplay, timeDisplay))
	help := helpStyle.Render("space: pause/resume • r: reset • q: quit")

	content := lipgloss.JoinVertical(
		lipgloss.Center,
		title,
		"",
		box,
		"",
		help,
	)

	// Center everything
	return lipgloss.Place(
		m.width,
		m.height,
		lipgloss.Center,
		lipgloss.Center,
		content,
	)
}

func (m model) renderTimer() string {
	// Dynamic colors based on time remaining
	var color string
	if m.duration <= 0 {
		color = "196" // Red
	} else {
		percentage := float64(m.duration) / float64(m.targetTime)
		if percentage > 0.5 {
			color = "82" // Green
		} else if percentage > 0.2 {
			color = "226" // Yellow
		} else {
			color = "208" // Orange
		}
	}

	titleStyle := lipgloss.NewStyle().
		Foreground(lipgloss.Color(color)).
		Bold(true).
		Padding(1, 0)

	timeStyle := lipgloss.NewStyle().
		Foreground(lipgloss.Color(color)).
		Bold(true)

	boxStyle := lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(lipgloss.Color(color)).
		Padding(1, 4).
		Align(lipgloss.Center)

	progressStyle := lipgloss.NewStyle().
		Foreground(lipgloss.Color(color))

	helpStyle := lipgloss.NewStyle().
		Foreground(lipgloss.Color("241")).
		Padding(1, 0)

	// Format time
	timeStr := formatDuration(m.duration, false)

	// State indicator
	var stateStr string
	if m.duration <= 0 {
		if m.state == statePaused {
			stateStr = "⏸ EXPIRED (PAUSED)"
		} else {
			stateStr = "🔔 TIME'S UP!"
		}
	} else if m.state == stateRunning {
		stateStr = "▶ RUNNING"
	} else {
		stateStr = " ⏸ PAUSED"
	}

	stateStyle := lipgloss.NewStyle().
		Foreground(lipgloss.Color(color)).
		Padding(0, 0, 1, 0)

	// Progress bar
	percentage := float64(m.duration) / float64(m.targetTime)
	if (percentage <= 0) {
		percentage = 0;
	}
	barWidth := 40
	filled := int(percentage * float64(barWidth))
	if filled > barWidth {
		filled = barWidth
	}
	if filled < 0 {
		filled = 0
	}

	bar := strings.Repeat("█", filled) + strings.Repeat("░", barWidth-filled)
	percentStr := fmt.Sprintf("%.02f%%", percentage*100)
	progressBar := progressStyle.Render(fmt.Sprintf("%s %s", bar, percentStr))

	// Build content
	title := titleStyle.Render("COUNTDOWN TIMER")
	stateDisplay := stateStyle.Render(stateStr)
	timeDisplay := timeStyle.Render(timeStr)
	boxContent := lipgloss.JoinVertical(lipgloss.Center, stateDisplay, timeDisplay)
	box := boxStyle.Render(boxContent)
	help := helpStyle.Render("space: pause/resume • r: reset • q: quit")

	content := lipgloss.JoinVertical(
		lipgloss.Center,
		title,
		"",
		box,
		"",
		progressBar,
		"",
		help,
	)

	// Center everything
	return lipgloss.Place(
		m.width,
		m.height,
		lipgloss.Center,
		lipgloss.Center,
		content,
	)
}

func formatDuration(d time.Duration, showMillis bool) string {
	sign := ""
	if d < 0 {
		sign = "-"
		d = -d
	}

	d = d.Round(10 * time.Millisecond)
	h := d / time.Hour
	d -= h * time.Hour
	m := d / time.Minute
	d -= m * time.Minute
	s := d / time.Second
	d -= s * time.Second
	ms := d / (10 * time.Millisecond)

	if showMillis {
		return fmt.Sprintf("%s%02d:%02d:%02d.%02d", sign, h, m, s, ms)
	}
	return fmt.Sprintf("%s%02d:%02d:%02d", sign, h, m, s)
}

func parseDuration(s string) (time.Duration, error) {
	// Handle formats like "5m", "1h30m", "90s", "2h15m30s"
	s = strings.TrimSpace(s)
	s = strings.TrimPrefix(s, "--")
	
	// Check if it's already in a format time.ParseDuration understands
	if d, err := time.ParseDuration(s); err == nil {
		return d, nil
	}

	// Try to parse common formats
	re := regexp.MustCompile(`(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?`)
	matches := re.FindStringSubmatch(s)
	
	if len(matches) == 0 {
		return 0, fmt.Errorf("invalid duration format: %s", s)
	}

	var total time.Duration
	if matches[1] != "" {
		h, _ := strconv.Atoi(matches[1])
		total += time.Duration(h) * time.Hour
	}
	if matches[2] != "" {
		m, _ := strconv.Atoi(matches[2])
		total += time.Duration(m) * time.Minute
	}
	if matches[3] != "" {
		s, _ := strconv.Atoi(matches[3])
		total += time.Duration(s) * time.Second
	}

	if total == 0 {
		return 0, fmt.Errorf("invalid duration format: %s", s)
	}

	return total, nil
}

// terminalBundleID returns the macOS bundle identifier for the current terminal app.
func terminalBundleID() string {
	bundleIDs := map[string]string{
		"ghostty":        "com.mitchellh.ghostty",
		"iTerm.app":      "com.googlecode.iterm2",
		"Apple_Terminal":  "com.apple.Terminal",
		"WezTerm":        "com.wez.wezterm",
		"Alacritty":      "org.alacritty",
		"kitty":          "net.kovidgoyal.kitty",
	}

	termProgram := os.Getenv("TERM_PROGRAM")
	if id, ok := bundleIDs[termProgram]; ok {
		return id
	}
	return "com.apple.Terminal"
}

// sendNotification sends a desktop notification using platform-native tools.
// On macOS, prefers terminal-notifier so clicking "Show" activates the terminal.
// Falls back silently if the notification command is unavailable.
func sendNotification(title, message string) {
	switch runtime.GOOS {
	case "darwin":
		// prefer terminal-notifier: supports click-to-activate and icons
		if path, err := exec.LookPath("terminal-notifier"); err == nil {
			exec.Command(path,
				"-title", title,
				"-message", message,
				"-sound", "default",
				"-appIcon", "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/Clock.icns",
				"-activate", terminalBundleID(),
			).Start()
			return
		}
		// fallback to osascript
		script := fmt.Sprintf(`display notification "%s" with title "%s"`, message, title)
		exec.Command("osascript", "-e", script).Start()
	case "linux":
		exec.Command("notify-send", title, message).Start()
	}
}

// playSound plays an attention-getting sound or terminal bell.
func playSound() {
	switch runtime.GOOS {
	case "darwin":
		// Use a built-in macOS sound
		exec.Command("afplay", "/System/Library/Sounds/Glass.aiff").Start()
	case "windows":
		// Use powershell to play a beep on windows
		exec.Command("powershell", "-c", "[console]::beep(440,500)").Start()
	default:
		// Fallback to terminal bell for Linux and others
		fmt.Print("\a")
	}
}

func main() {
	var m model

	// Parse command line arguments
	if len(os.Args) > 1 {
		arg := os.Args[1]
		
		// Check for stopwatch mode
		if arg == "--stopwatch" || arg == "--start" || arg == "-s" {
			m.mode = modeStopwatch
			m.state = stateRunning
			m.lastTick = time.Now()
		} else {
			// Try to parse as duration for timer mode
			duration, err := parseDuration(arg)
			if err != nil {
				fmt.Fprintf(os.Stderr, "Error: %v\n", err)
				fmt.Fprintf(os.Stderr, "\nUsage:\n")
				fmt.Fprintf(os.Stderr, "  timer                 Start in interactive mode\n")
				fmt.Fprintf(os.Stderr, "  timer --stopwatch     Start stopwatch\n")
				fmt.Fprintf(os.Stderr, "  timer --start         Start stopwatch (alias)\n")
				fmt.Fprintf(os.Stderr, "  timer 5m              Start 5-minute countdown\n")
				fmt.Fprintf(os.Stderr, "  timer 1h30m           Start 1h30m countdown\n")
				fmt.Fprintf(os.Stderr, "  timer 90s             Start 90-second countdown\n")
				os.Exit(1)
			}
			
			m.mode = modeTimer
			m.duration = duration
			m.targetTime = duration
			m.state = stateRunning
			m.lastTick = time.Now()
		}
	} else {
		// Interactive mode - default to stopwatch
		m.mode = modeStopwatch
		m.state = statePaused
	}

	p := tea.NewProgram(m, tea.WithAltScreen())
	if _, err := p.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}
