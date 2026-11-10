# archlinux-home-manager

Qubes OS の Arch Linux TemplateVM に Nix と Home Manager を導入し、アプリとドットファイルを宣言的に管理するためのリポジトリです。

## 仕組み

```
TemplateVM (archlinux)                     AppVM (このテンプレートを使う VM)
┌──────────────────────────────┐          ┌──────────────────────────────────┐
│ /nix  ← install.sh でビルド  │ ──継承──▶ │ /nix  (読み取り専用相当・再起動で戻る) │
│   └ gcroots/qubes-home-manager│          │                                  │
│ /home/user ← HM 適用         │          │ /home/user (AppVM 独自ボリューム)  │
└──────────────────────────────┘          │   ▲ 起動時に home-manager-qubes   │
                                           │     .service が activate する     │
                                           └──────────────────────────────────┘
```

- Nix は pacman の公式 `nix` パッケージで入れます。nix-daemon を使う multi-user 構成です。
- `/nix` はルートボリュームにあるため、テンプレートでビルドしたものは AppVM からそのまま使えます。
- AppVM の `/home` はテンプレートとは別のボリュームです。そのため AppVM の起動時に `home-manager-qubes.service` が activate スクリプトを実行し、シンボリックリンクを張ります。ビルドもネットワークも不要です。
- TemplateVM はネットワークを持たないので、nix-daemon は Qubes の updates proxy (`127.0.0.1:8082`) を経由してキャッシュを取得します。

## ディレクトリ構成

```
.
├── install.sh        # TemplateVM で実行するセットアップ / 再適用スクリプト
├── flake.nix         # nixpkgs / home-manager の入力と homeConfigurations
├── flake.lock        # 初回ビルド時に生成 (コミット推奨)
├── home.nix          # Home Manager のエントリポイント
└── pkgs/
    ├── default.nix   # pkgs/ 配下のモジュールをまとめて import
    ├── neovim.nix    # Neovim の設定
    ├── fcitx5.nix    # 日本語入力 (fcitx5 + mozc)
    ├── veracrypt.nix # VeraCrypt
    ├── gimp.nix      # GIMP
    ├── loupe.nix     # GNOME Image Viewer (Loupe)
    ├── ghostty.nix   # Ghostty
    └── zsh.nix       # zsh の設定
```

## セットアップ

1. このリポジトリを TemplateVM に持ち込みます。テンプレートはネットワークを持たないため、別の VM で clone してから `qvm-copy` で送ります。
   ```sh
   # 別の AppVM で
   git clone https://github.com/Restoration/archlinux-home-manager.git
   qvm-copy archlinux-home-manager   # 送り先にテンプレートを選択
   ```
2. TemplateVM で `user` として実行します。
   ```sh
   mv ~/QubesIncoming/*/archlinux-home-manager ~/
   cd ~/archlinux-home-manager
   ./install.sh
   ```
3. TemplateVM をシャットダウンし、このテンプレートを使う AppVM を再起動します。
4. Nix で入れた GUI アプリを Qubes のメニューに出したい場合は、dom0 で次を実行します。
   ```sh
   qvm-sync-appmenus <template-name>
   ```

## アプリの追加・設定変更

すべて **TemplateVM 上で** 行い、最後に `./install.sh` を再実行します。何度実行しても問題ありません。

### 単純にパッケージを入れるだけ

`home.nix` の `home.packages` に追加します。

```nix
home.packages = with pkgs; [
  git
  htop   # 追加
];
```

### 設定ごと管理したいアプリ

`pkgs/` にモジュールを作り、`pkgs/default.nix` の `imports` に追加します。

```nix
# pkgs/tmux.nix
{ ... }:
{
  programs.tmux = {
    enable = true;
    mouse = true;
  };
}
```

```nix
# pkgs/default.nix
{
  imports = [
    ./neovim.nix
    ./tmux.nix
  ];
}
```

利用できるオプションは [Home Manager Option Search](https://home-manager-options.extranix.com/) で調べられます。

### パッケージの更新

```sh
nix flake update     # flake.lock を更新
./install.sh
```

## カスタマイズ

| 環境変数                  | 既定値                    | 説明                                  |
| ------------------------- | ------------------------- | ------------------------------------- |
| `HM_USER`                 | 実行ユーザー名            | 適用する `homeConfigurations.<name>`  |
| `QUBES_PROXY`             | `http://127.0.0.1:8082`   | updates proxy の URL                  |
| `HOME_MANAGER_BACKUP_EXT` | `hm-bak`                  | 既存ファイルを退避するときの拡張子    |

`user` 以外のユーザーで使う場合は、`flake.nix` に `homeConfigurations.<name> = mkHome "<name>";` を追加してください。

## 注意点

- AppVM で `nix shell` や `nix profile install` を使うと、取得したものは `/nix` に置かれますが、再起動で消えます。残したいものは必ずテンプレートの設定に書いてください。
- `~/.bashrc` など、Home Manager の管理対象と重なる既存ファイルは `*.hm-bak` という名前で退避されます。
- AppVM 側の状態は次のコマンドで確認できます。
  ```sh
  systemctl status home-manager-qubes.service
  journalctl -u home-manager-qubes.service
  ```

## アンインストール

```sh
sudo systemctl disable --now home-manager-qubes.service nix-daemon.socket
sudo rm -f /etc/systemd/system/home-manager-qubes.service \
           /etc/systemd/system/nix-daemon.service.d/qubes-proxy.conf \
           /etc/profile.d/nix-home-manager.sh \
           /nix/var/nix/gcroots/qubes-home-manager
sudo rm -rf /usr/local/lib/qubes-nix
sudo sed -i -E '/^(GTK_IM_MODULE|QT_IM_MODULE|XMODIFIERS|SDL_IM_MODULE)=/d' /etc/environment
sudo usermod -s /bin/bash user
sudo pacman -Rns nix
sudo rm -rf /nix
```
