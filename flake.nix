{
  description = "Zig development environment";

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
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            zig
            # Common development tools
            zls # Zig Language Server
            gdb
            lldb
          ];

          shellHook = ''
            echo "Zig development environment loaded!"
            echo "Zig version: $(zig version)"
          '';
        };
      });
}
