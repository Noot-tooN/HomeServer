{
  description = "My NixOS Configuration";

  inputs = {
    # Official NixOS package source
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # Unstable NixOS packages
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    comin = {
      url = "github:nlewo/comin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Home Manager for declarative user configuration
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    nixpkgs,
    nixpkgs-unstable,
    home-manager,
    comin,
    ...
  }: let
    system = "x86_64-linux";
    pkgsUnstable = import nixpkgs-unstable {
      inherit system;
      config.allowUnfree = true;
    };
    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };
  in {
    nixosConfigurations.desktop = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        comin.nixosModules.comin
        ./modules/comin.nix
        ./modules/failure-reporting.nix
        {services.comin.package = comin.packages.${system}.comin;}
        ./hosts/desktop/configuration.nix
        home-manager.nixosModules.home-manager

        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "backup";
          home-manager.users.nirdala = import ./users/nirdala/home.nix {
            inherit pkgs pkgsUnstable;
          };
        }
      ];
      specialArgs = {
        inherit pkgsUnstable;
      };
    };
  };
}
