{
  description = "k0s - The Zero Friction Kubernetes for NixOS";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs =
    { self, nixpkgs, ... }:
    let

      genPackages =
        system: pkgs:
        let
          sourceBuilds = pkgs.callPackage ./k0s/source.nix { };
        in
        rec {
          inherit (pkgs.callPackage ./k0s/default.nix { })
            k0s_1_33
            k0s_1_34
            k0s_1_35
            k0s_1_36
            ;
          k0s = k0s_1_35;
        }
        // lib.optionalAttrs (buildsFromSource system) (
          # Keyed from the pins, not from `sourceBuilds`: this also runs as an
          # overlay, where naming an attribute out of `prev` recurses.
          lib.listToAttrs (
            map (minor: lib.nameValuePair "k0s-source_${minor}" sourceBuilds.withPayload.${minor}) minors
          )
        );

      lib = nixpkgs.lib;
      buildsFromSource = system: lib.elem system (import ./k0s/source-systems.nix);
      minors = (import ./k0s/embedded-bins/pins.nix { inherit lib; }).minors;
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
        lib.optionalAttrs (lib.elem system k0sSystems) (genPackages system pkgs)
        // {
          option-docs = import ./docs/options.nix {
            inherit nixpkgs pkgs;
            module = self.nixosModules.default;
          };
        }
      );

      overlays.default = final: prev: genPackages prev.stdenv.hostPlatform.system prev;

      nixosModules.default = ./nixos/k0s.nix;

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);

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
          embedded-bins = import ./checks/embedded-bins.nix { inherit lib pkgs; };
          embedded-bins-update = import ./checks/embedded-bins-update.nix { inherit lib pkgs; };
          embedded-bins-containerd = import ./checks/embedded-bins-containerd.nix { inherit lib pkgs; };
          embedded-bins-etcd = import ./checks/embedded-bins-etcd.nix { inherit lib pkgs; };
          embedded-bins-iptables = import ./checks/embedded-bins-iptables.nix { inherit lib pkgs; };
          embedded-bins-keepalived = import ./checks/embedded-bins-keepalived.nix { inherit lib pkgs; };
          embedded-bins-kine = import ./checks/embedded-bins-kine.nix { inherit lib pkgs; };
          embedded-bins-konnectivity = import ./checks/embedded-bins-konnectivity.nix {
            inherit lib pkgs;
          };
          embedded-bins-kubernetes = import ./checks/embedded-bins-kubernetes.nix { inherit lib pkgs; };
          embedded-bins-runc = import ./checks/embedded-bins-runc.nix { inherit lib pkgs; };
          source-packages = import ./checks/source-packages.nix {
            inherit lib pkgs;
            packages = self.packages.${system};
          };
        }
        # Reading these elsewhere throws, and `nix flake show` reads every system.
        // lib.optionalAttrs (buildsFromSource system) (
          {
            embedded-bins-payload = import ./checks/embedded-bins-payload.nix { inherit lib pkgs; };
            source-build = import ./checks/source-build.nix { inherit lib pkgs; };
          }
          # A VM per minor, rather than one per assembly path: cgo is on below
          # 1.35, and each minor stages a different etcd, runc and containerd,
          # so none stands in for another.
          // lib.listToAttrs (
            map (
              minor:
              lib.nameValuePair "source-build-vm-${minor}" (
                import ./checks/source-build-vm.nix { inherit lib pkgs minor; }
              )
            ) minors
          )
        )
      );

    };
}
