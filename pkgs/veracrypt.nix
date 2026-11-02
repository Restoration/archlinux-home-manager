# VeraCrypt (暗号化ボリューム)
#
# マウント時は VeraCrypt 自身が sudo で自分の実行ファイル (Nix store のフルパス)
# を root として起動する。Qubes の AppVM は sudo がパスワード不要なのでそのまま動く。
# カーネル側の dm_crypt / fuse は Qubes 標準カーネルに含まれている。
{ pkgs, ... }:

{
  # nixpkgs では unfree 扱い (flake.nix で allowUnfree = true 済み)
  home.packages = [ pkgs.veracrypt ];
}
