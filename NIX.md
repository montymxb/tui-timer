# Nix Flake Usage

This project includes a Nix flake for easy building and development across different systems.

## Prerequisites

- Nix with flakes enabled
- To enable flakes, add to your `~/.config/nix/nix.conf`:
  ```
  experimental-features = nix-command flakes
  ```

## Quick Start

### Run directly without installing

```bash
nix run github:montymxb/tui-timer
```

Or locally:

```bash
nix run .
```

### Run with arguments

```bash
# Start stopwatch
nix run . -- --stopwatch

# Start 5 minute timer
nix run . -- 5m
```

### Build the application

```bash
nix build
./result/bin/timer
```

### Development shell

Enter a development environment with Go and dev tools:

```bash
nix develop
```

Inside the dev shell you can:

```bash
go build -o timer    # build manually
go run main.go       # run directly
go test              # run tests
```

## Installing

### Install to your profile

```bash
nix profile install .
timer --stopwatch
```

### Add to your NixOS/home-manager configuration

```nix
{
  inputs.tui-timer.url = "github:yourusername/tui-timer";

  # In your packages or home.packages:
  environment.systemPackages = [
    inputs.tui-timer.packages.${system}.default
  ];
}
```
