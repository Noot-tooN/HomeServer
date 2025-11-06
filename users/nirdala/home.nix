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

  home.packages = with pkgs; [
    ncdu
  ];

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.starship = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.kitty = {
    enable = true;
    settings = {
      window_padding_width = 10;

      font_size = 14;
    };
    themeFile = "tokyo_night_night";
  };
}
