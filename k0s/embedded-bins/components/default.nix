{ lib, callPackage }:
let
  pins = import ../pins.nix { inherit lib; };

  # The JSON shape stops here: a component derivation takes the pins it needs
  # as arguments and knows nothing about the file they were read from.
  forMinor =
    minor:
    let
      containerdPin = (pins.read minor).upstream.components.containerd;
    in
    {
      containerd = callPackage ./containerd.nix {
        component = containerdPin;
        inherit ((pins.read minor).upstream) payloadBinaries;
        sources = {
          containerd = pins.fetch minor "containerd";
        }
        // lib.optionalAttrs (containerdPin ? extra_urls) {
          patch = pins.fetch minor "containerd/extra";
        };
      };

      etcd = callPackage ./etcd.nix {
        component = (pins.read minor).upstream.components.etcd;
        sources.etcd = pins.fetch minor "etcd";
      };

      iptables = callPackage ./iptables.nix {
        component = (pins.read minor).upstream.components.iptables;
        sources.iptables = pins.fetch minor "iptables";
      };

      keepalived = callPackage ./keepalived.nix {
        component = (pins.read minor).upstream.components.keepalived;
        sources.keepalived = pins.fetch minor "keepalived";
      };

      kine = callPackage ./kine.nix {
        component = (pins.read minor).upstream.components.kine;
        sources.kine = pins.fetch minor "kine";
      };

      konnectivity = callPackage ./konnectivity.nix {
        component = (pins.read minor).upstream.components.konnectivity;
        sources.konnectivity = pins.fetch minor "konnectivity";
      };

      kubernetes = callPackage ./kubernetes.nix {
        component = (pins.read minor).upstream.components.kubernetes;
        inherit ((pins.read minor).upstream) payloadBinaries;
        sources.kubernetes = pins.fetch minor "kubernetes";
      };

      runc = callPackage ./runc.nix {
        component = (pins.read minor).upstream.components.runc;
        sources = {
          runc = pins.fetch minor "runc";
          libseccomp = pins.fetch minor "runc/extra";
        };
      };
    };
in
lib.genAttrs pins.minors forMinor
