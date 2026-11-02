# zsh
#
# ログインシェルは pacman の /usr/bin/zsh を使い (install.sh が設定)、
# 設定 (~/.zshrc, ~/.zshenv) とプラグインを Home Manager で管理する。
# Nix の zsh をログインシェルにすると、AppVM で activate が失敗したときに
# ログインできなくなるため。
{ config, ... }:

{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    history = {
      size = 100000;
      save = 100000;
      path = "${config.xdg.dataHome}/zsh/history";
      ignoreDups = true;
      ignoreSpace = true;
      share = true;
      extended = true;
    };

    shellAliases = {
      ls = "ls --color=auto";
      ll = "ls -lh";
      la = "ls -lAh";
      grep = "grep --color=auto";
      hms = "~/archlinux-home-manager/install.sh";
    };

    initContent = ''
      bindkey -e

      setopt auto_cd
      setopt auto_pushd
      setopt pushd_ignore_dups
      setopt interactive_comments
      setopt no_beep

      # 補完: 大文字小文字を区別しない / メニュー選択
      zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
      zstyle ':completion:*' menu select

      # プロンプト: user@qube-name dir (git branch)
      autoload -Uz vcs_info
      zstyle ':vcs_info:git:*' formats ' %F{magenta}(%b)%f'
      precmd() { vcs_info }
      setopt prompt_subst
      PROMPT='%F{green}%n@%m%f %F{blue}%~%f''${vcs_info_msg_0_}
      %(?.%F{white}.%F{red})%#%f '
    '';
  };
}
