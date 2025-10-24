{ pkgs, lib, ... }:

let
  commonBuildInputs = [
    pkgs.pkg-config
    pkgs.openssl
  ] ++ (lib.optionals pkgs.stdenv.isDarwin [ pkgs.darwin.apple_sdk.frameworks.Security ]);

  pkgConfigPath = "${pkgs.openssl.dev}/lib/pkgconfig";

in
{
  inherit commonBuildInputs pkgConfigPath;
}
