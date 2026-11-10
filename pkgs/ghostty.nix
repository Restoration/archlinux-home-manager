# Ghostty (ターミナルエミュレータ)
#
# Ghostty は OpenGL 4.3 が必須。Nix のアプリは Arch 側の Mesa を使えないため、
# Home Manager の targets.genericLinux.gpu (既定で有効) が用意する Nix 版 Mesa を
# /run/opengl-driver に置く必要がある。この設定は install.sh が
# non-nixos-gpu-setup を実行して行う。
# Qubes の AppVM には GPU が無いので、描画は Mesa の llvmpipe (CPU) で行われる。
{ ... }:

{
  programs.ghostty = {
    enable = true;
    enableZshIntegration = true;
    settings = {
      font-size = 11;
    };
  };
}
