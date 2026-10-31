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

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Follow the fork's default branch; flake.lock pins each deployed revision.
    age-mnemonic.url = "github:Noot-tooN/age";

    quantum-secrets = {
      url = "github:Noot-tooN/QuantumSecrets";
      flake = false;
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
    sops-nix,
    age-mnemonic,
    quantum-secrets,
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
        sops-nix.nixosModules.sops
        ./modules/secrets.nix
        {environment.systemPackages = [age-mnemonic.packages.${system}.age-keygen-mnemonic];}
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
        inherit pkgsUnstable quantum-secrets;
      };
    };
  };
}
