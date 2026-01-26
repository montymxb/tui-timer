{
  description = "Terminal-based stopwatch and countdown timer built with Go and Bubble Tea";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        packages.default = pkgs.buildGoModule {
          pname = "tui-timer";
          version = "0.1.0";

          src = ./.;

          # vendorHash is required for Go modules
          # calculated from go.mod/go.sum
          vendorHash = "sha256-zicQH9sCqkDu2HlqY2Ps7Wh3P7oM4/dP6ZhUI377lwc=";

          # metadata
          meta = with pkgs.lib; {
            description = "Terminal-based stopwatch and countdown timer";
            homepage = "https://github.com/montymxb/tui-timer";
            license = licenses.mit;
            mainProgram = "timer";
          };
        };

        # alias for packages.default
        packages.tui-timer = self.packages.${system}.default;

        # development shell with Go and other tools
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            go
            gopls
            gotools
            go-tools
          ];

          shellHook = ''
            echo "Go dev environment loaded"
            echo "Go version: $(go version)"
            echo ""
            echo "Run 'go build -o timer' to build the tui-timer"
            echo "Run 'go run main.go' to run directly"
          '';
        };

        # make it easy to run with `nix run`
        apps.default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/timer";
        };
      }
    );
}
