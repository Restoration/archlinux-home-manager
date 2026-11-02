# pkgs/ 配下のモジュールをまとめて読み込む
# アプリを追加したら imports に足す
{
  imports = [
    ./neovim.nix
    ./fcitx5.nix
    ./veracrypt.nix
  ];
}
