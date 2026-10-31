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
    ../../modules/fish.nix
  ];

  home.packages = with pkgs; [
    ncdu
  ];

  programs.kitty = {
    enable = true;
    settings = {
      window_padding_width = 10;

      font_size = 14;
    };
    themeFile = "tokyo_night_night";
  };
}
