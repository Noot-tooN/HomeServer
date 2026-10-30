{...}: let
in {
  programs.zsh = {
    enable = true;

    enableCompletion = true;

    oh-my-zsh = {
      enable = true;
      plugins = [
        "git"
      ];
    };

    syntaxHighlighting.enable = true;
    autosuggestion.enable = true;

    shellAliases = {
      # Emergency/manual rebuilds use the committed dependency versions.
      flake-switch-here = "sudo nixos-rebuild switch --flake .#desktop";
      flake-switch-etc = "(cd /etc/nixos && flake-switch-here)";
    };

    initContent = ''
      bindkey '^H' backward-kill-word
    '';
  };
}
