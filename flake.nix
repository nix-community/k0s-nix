{
  description = "k0s - The Zero Friction Kubernetes for NixOS";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs =
    { self, nixpkgs, ... }:
    let

      genPackages = pkgs: rec {
        inherit (pkgs.callPackage ./k0s/default.nix { })
          k0s_1_33
          k0s_1_34
          k0s_1_35
          k0s_1_36
          ;
        k0s = k0s_1_35;
      };

      lib = nixpkgs.lib;
      k0sSystems = [
        "armv7l-linux"
        "aarch64-linux"
        "x86_64-linux"
      ];
      darwinSystems = [
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      allSystems = k0sSystems ++ darwinSystems;
      # nixfmt is Haskell and nixpkgs has no GHC bootstrap for
      # armv7l-linux.
      formatterSystems = [
        "aarch64-linux"
        "x86_64-linux"
      ]
      ++ darwinSystems;
      forAllSystems = lib.genAttrs allSystems;
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        # k0s itself is a linux binary; the option documentation builds
        # anywhere.
        lib.optionalAttrs (lib.elem system k0sSystems) (genPackages pkgs)
        // {
          option-docs = import ./docs/options.nix {
            inherit nixpkgs pkgs;
            module = self.nixosModules.default;
          };
        }
      );

      overlays.default = final: prev: genPackages prev;

      nixosModules.default = ./nixos/k0s.nix;

      formatter = lib.genAttrs formatterSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);

      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          # Empty on darwin, where there is no k0s package to test.
          versions = builtins.filter (lib.hasPrefix "k0s_") (builtins.attrNames self.packages.${system});
          tests = map (name: lib.strings.removeSuffix ".nix" name) (
            builtins.attrNames (builtins.readDir ./tests)
          );
          forAllVersionsAndTests =
            check:
            let
              nestedPairs = map (
                version:
                map (test: {
                  name = "${version}_${test}";
                  value = check version test;
                }) tests
              ) versions;
              flatPairs = builtins.concatLists nestedPairs;
            in
            builtins.listToAttrs flatPairs;
        in
        forAllVersionsAndTests (
          version: test:
          pkgs.testers.runNixOSTest {
            imports = [ ./tests/${test}.nix ];
            node = {
              pkgsReadOnly = false;
            };
            defaults = {
              imports = [ self.nixosModules.default ];
              nixpkgs.overlays = [
                self.overlays.default
                (final: prev: {
                  inherit final;
                  k0s = prev."${version}";
                })
              ];
            };
          }
        )
        // builtins.listToAttrs (
          map (version: {
            name = "${version}_config-validate";
            value = import ./checks/config.nix {
              inherit lib pkgs nixpkgs;
              module = self.nixosModules.default;
              package = self.packages.${system}.${version};
            };
          }) versions
        )
        // {
          option-types = import ./checks/types.nix { inherit lib pkgs; };
          option-docs = self.packages.${system}.option-docs;
        }
        // lib.optionalAttrs (versions != [ ]) {
          readme-example = import ./checks/readme.nix {
            inherit lib nixpkgs pkgs;
            k0sNix = self;
          };
        }
      );

    };
}
