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
  };
}
