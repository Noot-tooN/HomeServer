{
  pkgs,
  pkgsUnstable,
  ...
}: {
  home.username = "nirdala";
  home.homeDirectory = "/home/nirdala";
  home.stateVersion = "25.05";

  programs.home-manager.enable = true;

  imports = [
    ../../modules/zsh.nix
  ];

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.starship = {
    enable = true;
    enableZshIntegration = true;
  };
}
