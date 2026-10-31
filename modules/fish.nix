{pkgs, ...}: let
  # An explicit interpreter keeps previews independent of the calling shell.
  preview = pkgs.writeShellScript "fzf-file-preview" ''
    if [ -d "$1" ]; then
      exec ${pkgs.eza}/bin/eza --tree --level=2 --icons --color=always -- "$1"
    else
      exec ${pkgs.bat}/bin/bat --color=always --style=numbers --line-range=:500 -- "$1"
    fi
  '';
in {
  home.packages = with pkgs; [bat eza fd];

  programs.fish = {
    enable = true;
    shellAbbrs = {
      ls = "eza";
      ll = "eza -la --icons --git";
      lt = "eza --tree --level=2 --icons";
      cat = "bat";
      find = "fd";
    };
    interactiveShellInit = ''
      set -g fish_greeting
      set -g fish_color_command 5fd75f
      set -g fish_color_builtin 5fd75f
      set -g fish_color_function 5fd75f
      set -g fish_color_keyword 5fd75f
      set -g fish_color_param normal
      set -g fish_color_option normal
      set -g fish_color_valid_path normal --underline
      bind ctrl-h backward-kill-word
    '';
  };

  programs.fzf = {
    enable = true;
    enableFishIntegration = true;
    enableBashIntegration = false;
    enableZshIntegration = false;
    fileWidgetCommand = "${pkgs.fd}/bin/fd --hidden --exclude .git --type file --type directory";
    fileWidgetOptions = ["--preview '${preview} {}'"];
  };

  programs.starship = {
    enable = true;
    enableFishIntegration = true;
    enableBashIntegration = false;
    enableZshIntegration = false;
    settings = builtins.fromTOML (builtins.readFile ./starship.toml);
  };
}
