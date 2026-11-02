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
    └── veracrypt.nix # VeraCrypt
```

## セットアップ

1. このリポジトリを TemplateVM に持ち込みます。テンプレートはネットワークを持たないため、別の VM で clone してから `qvm-copy` で送ります。
   ```sh
   # 別の AppVM で
   git clone <this-repo> archlinux-home-manager
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

## Neovim

`pkgs/neovim.nix` で管理しています。

- `nvim` / `vi` / `vim` / `vimdiff` は nvim のエイリアスで、`EDITOR=nvim` も設定されます。
- プラグイン: treesitter (全パーサー同梱), telescope, nvim-lspconfig, tokyonight
- LSP: `lua-language-server`, `nil` (Nix)
- 主なキーマップ (`<leader>` = Space)

  | キー          | 動作              |
  | ------------- | ----------------- |
  | `<leader>ff`  | ファイル検索      |
  | `<leader>fg`  | grep              |
  | `<leader>fb`  | バッファ一覧      |

プラグインは lazy.nvim などのプラグインマネージャは使わず、すべて Nix で管理します。追加するには `plugins` に `pkgs.vimPlugins.<name>` を足してください。そうすると AppVM でもネットワークなしで動きます。

## 日本語入力 (fcitx5 + mozc)

`pkgs/fcitx5.nix` で管理しています。

- fcitx5 の本体と mozc は Nix で入れます。
- Qubes の AppVM にはデスクトップ環境のセッションがないため、`~/.config/autostart/org.fcitx.Fcitx5.desktop` から起動します。起動は qubes-session が行います。
  - `/etc/xdg/autostart` に同じ名前のファイル (pacman 版) があっても、ユーザー側のこのファイルが優先されます。
- 入力の切り替えは `Ctrl+Space` か `半角/全角` です。
- キーボード配列は `us` にしています。JIS キーボードを使う場合は、`pkgs/fcitx5.nix` の `keyboardLayout` を `"jp"` に変えてください。
- 日本語フォントとして Noto CJK を入れ、fontconfig に登録しています。pacman で入れたアプリからも使えます。

`install.sh` はシステム側の設定も行います。

- pacman で入れた GTK/Qt アプリが fcitx5 を使えるよう、`fcitx5-gtk` と `fcitx5-qt` を pacman で入れます。
- `/etc/environment` に `GTK_IM_MODULE` / `QT_IM_MODULE` / `XMODIFIERS` / `SDL_IM_MODULE` を書き込みます。Qubes のアプリは qrexec 経由で起動されるため、ログインシェルの設定 (`/etc/profile.d` など) を読みません。そのため `/etc/environment` に書いています。

日本語入力が効かないときは、AppVM で次を確認してください。

```sh
pgrep -a fcitx5          # 起動しているか
fcitx5-diagnose | less   # 環境変数・IM モジュールの診断
```

## VeraCrypt

`pkgs/veracrypt.nix` で管理しています。GUI はアプリメニューに `VeraCrypt` として表示されます (`qvm-sync-appmenus` 後)。CLI は `veracrypt --text` で使えます。

- マウントするときは、VeraCrypt が `sudo` を使って自分自身を root として起動します。Qubes の AppVM は sudo にパスワードが要らないので、追加の設定はいりません。
- AppVM でマウントした内容は、その AppVM 内でしか見えません。また、AppVM をシャットダウンするとマウントも外れます。
- コンテナファイルは AppVM の `/home` (永続ボリューム) に置いてください。ほかの場所は再起動で消えます。
- USB デバイス上のボリュームを開くときは、dom0 で `qvm-block attach <appvm> <device>` を実行して、そのブロックデバイスを AppVM に割り当ててからマウントします。

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
sudo pacman -Rns nix
sudo rm -rf /nix
```
