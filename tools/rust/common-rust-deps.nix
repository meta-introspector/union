{ pkgs, lib, ... }:

let
  opensslDeps = import ./openssl-deps.nix { inherit pkgs lib; };
  inherit (opensslDeps) opensslBuildInputs opensslPkgConfigPath;

  commonBuildInputs = opensslBuildInputs ++ [
    pkgs.pkg-config
  ];

  pkgConfigPath = opensslPkgConfigPath;

in
{
  inherit commonBuildInputs pkgConfigPath;
}
