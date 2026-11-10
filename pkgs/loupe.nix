# GNOME Image Viewer (Loupe)
#
# GNOME 45 以降の標準画像ビューア (旧 Eye of GNOME / eog の後継)。
{ pkgs, ... }:

{
  home.packages = [ pkgs.loupe ];
}
