{ lib }:
let
  minors = lib.pipe (builtins.readDir ./.) [
    (lib.filterAttrs (name: _: lib.hasSuffix ".json" name))
    builtins.attrNames
    (map (lib.removeSuffix ".json"))
  ];

  read = minor: builtins.fromJSON (builtins.readFile (./. + "/${minor}.json"));

  fetch =
    minor: name:
    lib.findFirst (
      entry: entry.name == name
    ) (throw "${minor}.json records no source named ${name}") (read minor).fetch;
in
{
  inherit minors read fetch;
}
