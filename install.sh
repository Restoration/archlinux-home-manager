#!/usr/bin/env bash
#
# Qubes OS の Arch Linux TemplateVM に Nix + Home Manager を導入するスクリプト
#
# 使い方 (TemplateVM 内で、通常ユーザー "user" として実行):
#   ./install.sh            # 初回インストール / 設定の再適用 (何度実行しても安全)
#
# 仕組み:
#   - Nix は pacman の公式パッケージ (multi-user / nix-daemon) で入れる。
#     /nix はルートボリュームにあるので、テンプレートから AppVM へそのまま継承される。
#   - テンプレートで Home Manager の activationPackage をビルドし、
#     /nix/var/nix/gcroots/qubes-home-manager に GC root として固定する。
#   - AppVM の /home はテンプレートとは別ボリュームなので、AppVM 起動時に
#     systemd サービスが activate スクリプトを実行してドットファイルのリンクを張る。
#     (ストアパスは既にテンプレートで揃っているため、ネットワーク不要・ビルド不要)
#   - TemplateVM はネットワークを持たないので、Qubes の updates proxy
#     (127.0.0.1:8082) 経由で nix-daemon が substituter にアクセスする。
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HM_USER="${HM_USER:-$(id -un)}"
QUBES_PROXY="${QUBES_PROXY:-http://127.0.0.1:8082}"
GCROOT="/nix/var/nix/gcroots/qubes-home-manager"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/qubes-home-manager"
BACKUP_EXT="${HOME_MANAGER_BACKUP_EXT:-hm-bak}"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 前提チェック
# ---------------------------------------------------------------------------
[[ "$(id -u)" -ne 0 ]] || die "root ではなく通常ユーザー (例: user) で実行してください。"
command -v pacman >/dev/null || die "pacman が見つかりません。Arch Linux 用のスクリプトです。"
command -v sudo   >/dev/null || die "sudo が必要です。"

QUBES_VM_TYPE=""
if command -v qubesdb-read >/dev/null 2>&1; then
  QUBES_VM_TYPE="$(qubesdb-read /type 2>/dev/null || true)"
fi

if [[ "$QUBES_VM_TYPE" == "TemplateVM" ]]; then
  log "TemplateVM を検出: updates proxy ($QUBES_PROXY) を使用します"
  export http_proxy="$QUBES_PROXY" https_proxy="$QUBES_PROXY"
  export HTTP_PROXY="$QUBES_PROXY" HTTPS_PROXY="$QUBES_PROXY"
elif [[ -n "$QUBES_VM_TYPE" ]]; then
  warn "現在の VM タイプは '$QUBES_VM_TYPE' です。通常は TemplateVM で実行します。"
  warn "AppVM で実行した変更 (/nix 等) は再起動で消えます。"
else
  warn "Qubes 環境を検出できませんでした。通常の Arch Linux として続行します。"
fi

[[ -f "$REPO_DIR/flake.nix" ]] || die "$REPO_DIR/flake.nix がありません。"

# ---------------------------------------------------------------------------
# 1. Nix のインストール
# ---------------------------------------------------------------------------
log "pacman で nix をインストール"
sudo pacman -Sy --needed --noconfirm nix

log "/etc/nix/nix.conf を設定"
ensure_nix_conf() {
  local key="$1" value="$2"
  if sudo grep -qE "^[[:space:]]*${key}[[:space:]]*=" /etc/nix/nix.conf; then
    sudo sed -i -E "s|^[[:space:]]*${key}[[:space:]]*=.*|${key} = ${value}|" /etc/nix/nix.conf
  else
    echo "${key} = ${value}" | sudo tee -a /etc/nix/nix.conf >/dev/null
  fi
}
ensure_nix_conf experimental-features "nix-command flakes"
ensure_nix_conf auto-optimise-store "true"

# ---------------------------------------------------------------------------
# 2. nix-daemon を updates proxy 経由で通信させる (TemplateVM の時だけ有効)
# ---------------------------------------------------------------------------
log "nix-daemon 用の Qubes proxy 設定をインストール"
sudo install -d -m 0755 /usr/local/lib/qubes-nix
sudo tee /usr/local/lib/qubes-nix/proxy-env >/dev/null <<EOF
#!/bin/sh
# TemplateVM のときだけ updates proxy を nix-daemon に渡す
: > /run/nix-daemon-proxy.env
if [ "\$(qubesdb-read /type 2>/dev/null)" = "TemplateVM" ]; then
  cat > /run/nix-daemon-proxy.env <<ENV
http_proxy=${QUBES_PROXY}
https_proxy=${QUBES_PROXY}
HTTP_PROXY=${QUBES_PROXY}
HTTPS_PROXY=${QUBES_PROXY}
ENV
fi
EOF
sudo chmod 0755 /usr/local/lib/qubes-nix/proxy-env

sudo install -d -m 0755 /etc/systemd/system/nix-daemon.service.d
sudo tee /etc/systemd/system/nix-daemon.service.d/qubes-proxy.conf >/dev/null <<'EOF'
[Service]
ExecStartPre=/usr/local/lib/qubes-nix/proxy-env
EnvironmentFile=-/run/nix-daemon-proxy.env
EOF

log "nix-daemon を有効化"
sudo systemctl daemon-reload
sudo systemctl enable nix-daemon.socket
sudo systemctl restart nix-daemon.socket
sudo systemctl stop nix-daemon.service 2>/dev/null || true  # 次の接続で proxy 設定付きで再起動される

# ---------------------------------------------------------------------------
# 3. ユーザーを nix-users グループへ
# ---------------------------------------------------------------------------
if ! id -nG "$HM_USER" | tr ' ' '\n' | grep -qx nix-users; then
  log "$HM_USER を nix-users グループに追加"
  sudo usermod -aG nix-users "$HM_USER"
fi

# グループ追加直後は現在のシェルに反映されないので sg 経由で実行する
run_nix() {
  if id -nG | tr ' ' '\n' | grep -qx nix-users; then
    "$@"
  else
    sg nix-users -c "$(printf '%q ' "$@")"
  fi
}

# ---------------------------------------------------------------------------
# 4. Home Manager 構成をビルドして適用
# ---------------------------------------------------------------------------
FLAKE_REF="path:${REPO_DIR}#homeConfigurations.\"${HM_USER}\".activationPackage"
mkdir -p "$STATE_DIR"

log "Home Manager 構成をビルド: $FLAKE_REF"
run_nix nix build --print-build-logs --out-link "$STATE_DIR/activation" "$FLAKE_REF"
ACTIVATION="$(readlink -f "$STATE_DIR/activation")"

log "Home Manager を適用 (TemplateVM の /home/$HM_USER)"
run_nix env HOME_MANAGER_BACKUP_EXT="$BACKUP_EXT" "$ACTIVATION/activate"

log "GC root を作成: $GCROOT -> $ACTIVATION"
sudo ln -sfn "$ACTIVATION" "$GCROOT"

# ---------------------------------------------------------------------------
# 5. AppVM 起動時に Home Manager を activate する systemd サービス
# ---------------------------------------------------------------------------
HM_HOME="$(getent passwd "$HM_USER" | cut -d: -f6)"

log "home-manager-qubes.service をインストール"
sudo tee /etc/systemd/system/home-manager-qubes.service >/dev/null <<EOF
[Unit]
Description=Activate Home Manager configuration for ${HM_USER} (Qubes AppVM)
Requires=nix-daemon.socket
After=nix-daemon.socket qubes-mount-dirs.service local-fs.target
Wants=qubes-mount-dirs.service
Before=qubes-gui-agent.service
ConditionPathExists=${GCROOT}/activate

[Service]
Type=oneshot
RemainAfterExit=yes
# TemplateVM ではインストール時に適用済みなのでスキップ
ExecCondition=/bin/sh -c '[ "\$(qubesdb-read /type 2>/dev/null)" != "TemplateVM" ]'
ExecStart=/usr/bin/runuser -u ${HM_USER} -- /usr/bin/env HOME=${HM_HOME} USER=${HM_USER} HOME_MANAGER_BACKUP_EXT=${BACKUP_EXT} ${GCROOT}/activate

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable home-manager-qubes.service

# ---------------------------------------------------------------------------
# 6. ログインシェルで Nix / Home Manager の環境を読み込む
# ---------------------------------------------------------------------------
log "/etc/profile.d/nix-home-manager.sh をインストール"
sudo tee /etc/profile.d/nix-home-manager.sh >/dev/null <<'EOF'
# Nix / Home Manager (installed by archlinux-home-manager/install.sh)
for _p in "$HOME/.nix-profile" "${XDG_STATE_HOME:-$HOME/.local/state}/nix/profile"; do
  if [ -d "$_p/bin" ]; then
    case ":$PATH:" in *":$_p/bin:"*) ;; *) PATH="$_p/bin:$PATH" ;; esac
    XDG_DATA_DIRS="$_p/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
    if [ -r "$_p/etc/profile.d/hm-session-vars.sh" ]; then
      . "$_p/etc/profile.d/hm-session-vars.sh"
    fi
    break
  fi
done
unset _p
export PATH XDG_DATA_DIRS
EOF

# ---------------------------------------------------------------------------
# 7. 日本語入力 (fcitx5 本体は Home Manager 側。ここではシステム側の設定)
# ---------------------------------------------------------------------------
# pacman で入れた GTK/Qt アプリが fcitx5 と通信するための IM モジュール
log "fcitx5 の IM モジュール (pacman アプリ用) をインストール"
sudo pacman -S --needed --noconfirm fcitx5-gtk fcitx5-qt

# Qubes のアプリは qrexec 経由で起動されログインシェルを通らないため、
# pam_env が読む /etc/environment に設定する
log "/etc/environment に入力メソッドの環境変数を設定"
ensure_env() {
  local key="$1" value="$2"
  sudo touch /etc/environment
  if sudo grep -qE "^${key}=" /etc/environment; then
    sudo sed -i -E "s|^${key}=.*|${key}=${value}|" /etc/environment
  else
    echo "${key}=${value}" | sudo tee -a /etc/environment >/dev/null
  fi
}
ensure_env GTK_IM_MODULE fcitx
ensure_env QT_IM_MODULE fcitx
ensure_env XMODIFIERS "@im=fcitx"
ensure_env SDL_IM_MODULE fcitx

cat <<EOF

$(printf '\033[1;32m')完了しました。$(printf '\033[0m')

次の手順:
  1. TemplateVM をシャットダウンする
  2. このテンプレートを使う AppVM を再起動する
     -> 起動時に home-manager-qubes.service が設定を適用します
  3. (任意) dom0 で Qubes メニューにアプリを反映:
       qvm-sync-appmenus <template-name>

設定を変更したら、TemplateVM でこのスクリプトを再実行してください:
  ${REPO_DIR}/install.sh
EOF
