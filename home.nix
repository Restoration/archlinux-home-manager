{ pkgs, username, ... }:

{
  imports = [ ./pkgs ];

  home.username = username;
  home.homeDirectory = "/home/${username}";

  # 初回導入時の Home Manager リリースに合わせる。後から安易に変えないこと。
  home.stateVersion = "25.05";

  # 非 NixOS (Arch) 向けの調整: XDG_DATA_DIRS, ロケール等
  targets.genericLinux.enable = true;

  # home-manager コマンド自体も管理する
  programs.home-manager.enable = true;

  # ここに管理したいアプリを追加する
  home.packages = with pkgs; [
    git
    ripgrep
    fd
    jq
  ];

  programs.bash.enable = true;
}
