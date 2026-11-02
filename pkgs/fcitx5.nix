# 日本語入力 (fcitx5 + mozc)
#
# Qubes の AppVM には DE のセッションが無いため、graphical-session.target に
# 依存する systemd ユーザーサービスではなく XDG autostart で fcitx5 を起動する。
# (qubes-session が ~/.config/autostart を実行する)
#
# Arch (pacman) 側の GTK/Qt アプリ用の IM モジュール (fcitx5-gtk, fcitx5-qt) と
# GTK_IM_MODULE などの環境変数は install.sh がシステム側に設定する。
{ config, pkgs, ... }:

let
  # キーボード配列: JIS キーボードなら "jp" にする
  keyboardLayout = "us";
in
{
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5 = {
      addons = with pkgs; [
        fcitx5-mozc
        fcitx5-gtk
      ];

      settings = {
        # ~/.config/fcitx5/profile
        inputMethod = {
          GroupOrder."0" = "Default";
          "Groups/0" = {
            Name = "Default";
            "Default Layout" = keyboardLayout;
            DefaultIM = "mozc";
          };
          "Groups/0/Items/0" = {
            Name = "keyboard-${keyboardLayout}";
            Layout = "";
          };
          "Groups/0/Items/1" = {
            Name = "mozc";
            Layout = "";
          };
        };

        # ~/.config/fcitx5/config
        globalOptions = {
          Hotkey = {
            # 入力メソッドの切り替え
            "TriggerKeys/0" = "Control+space";
            "TriggerKeys/1" = "Zenkaku_Hankaku";
          };
          Behavior = {
            # ウィンドウ (Qube) ごとに状態を共有しない
            ShareInputState = "No";
          };
        };
      };
    };
  };

  # Qubes AppVM では XDG autostart から起動する
  xdg.configFile."autostart/org.fcitx.Fcitx5.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Fcitx 5
    Exec=${config.i18n.inputMethod.package}/bin/fcitx5 -d
    X-GNOME-AutoRestart=false
    NoDisplay=true
  '';

  # 日本語フォント (Arch 側のアプリからも見えるよう fontconfig に登録)
  fonts.fontconfig.enable = true;
  home.packages = with pkgs; [
    noto-fonts-cjk-sans
    noto-fonts-cjk-serif
  ];
}
