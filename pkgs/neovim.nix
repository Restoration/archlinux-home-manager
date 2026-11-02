{ pkgs, ... }:

{
  programs.neovim = {
    enable = true;
    defaultEditor = true; # EDITOR=nvim
    viAlias = true;
    vimAlias = true;
    vimdiffAlias = true;

    # LSP やフォーマッタなど、neovim からだけ使うツール
    extraPackages = with pkgs; [
      ripgrep
      fd
      lua-language-server
      nil # Nix LSP
      nixfmt-rfc-style
    ];

    plugins = with pkgs.vimPlugins; [
      nvim-treesitter.withAllGrammars
      telescope-nvim
      plenary-nvim
      nvim-lspconfig
      tokyonight-nvim
    ];

    extraLuaConfig = ''
      vim.g.mapleader = " "

      local o = vim.opt
      o.number = true
      o.relativenumber = true
      o.expandtab = true
      o.shiftwidth = 2
      o.tabstop = 2
      o.smartindent = true
      o.ignorecase = true
      o.smartcase = true
      o.termguicolors = true
      o.clipboard = "unnamedplus"
      o.undofile = true

      vim.cmd.colorscheme("tokyonight")

      -- パーサーは withAllGrammars で Nix から供給済み。組み込み API で有効化する
      vim.api.nvim_create_autocmd("FileType", {
        callback = function(args)
          pcall(vim.treesitter.start, args.buf)
        end,
      })

      local builtin = require("telescope.builtin")
      vim.keymap.set("n", "<leader>ff", builtin.find_files, { desc = "Find files" })
      vim.keymap.set("n", "<leader>fg", builtin.live_grep, { desc = "Live grep" })
      vim.keymap.set("n", "<leader>fb", builtin.buffers, { desc = "Buffers" })

      vim.lsp.enable({ "lua_ls", "nil_ls" })
    '';
  };
}
