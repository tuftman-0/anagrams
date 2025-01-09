# zig development environment nix shell template
{pkgs ? import <nixpkgs> {}}:
pkgs.mkShell {
  # zig = zig_overlay.packages.${system}.master;
  buildInputs = with pkgs; [
    zig
    zls
    lldb
  ];
}
