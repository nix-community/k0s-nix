{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    k0s-nix.url = "github:nix-community/k0s-nix";
    k0s-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { nixpkgs, k0s-nix, ... }:
    {
      nixosConfigurations.my-node = nixpkgs.lib.nixosSystem {
        modules = [
          ./hardware-configuration.nix
          k0s-nix.nixosModules.default
          {
            nixpkgs.overlays = [ k0s-nix.overlays.default ];

            services.k0s = {
              enable = true;
              role = "single";
              spec.api.address = "192.0.2.1";
            };

            system.stateVersion = "26.05";
          }
        ];
      };
    };
}
