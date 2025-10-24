{ pkgs
, lib'
, crane
, cargoWorkspaceAttrs
, cargoArtifacts
, allCargoTomls
, dbg
, ...
}: {
  cargo-workspace-clippy = crane.lib.cargoClippy (
    cargoWorkspaceAttrs // {
      inherit cargoArtifacts;
    }
  );
  cargo-workspace-test = crane.lib.cargoTest (
    cargoWorkspaceAttrs // {
      inherit cargoArtifacts;
    }
  );
  cargo-workspace-doc = crane.lib.mkCargoDerivation (
    cargoWorkspaceAttrs // {
      buildPhaseCargoCommand = ''
        cargo doc --workspace --no-deps
      '';
      inherit cargoArtifacts;
    }
  );
  # NOTE: This is currently broken, as some crate features are not working properly
  all-crates-buildable-individually = crane.lib.mkCargoDerivation (
    (builtins.removeAttrs cargoWorkspaceAttrs [ "cargoTestExtraArgs" "cargoClippyExtraArgs" ]) // {
      inherit cargoArtifacts;
      pname = "cargo-workspace-individual-check";
      # strictDeps = true;
      passAsFile = [ "actualBuildPhase" ];
      buildPhaseCargoCommand = null;
      buildPhase = ''
        . "$actualBuildPhasePath"
      '';
      # if we don't do this (and pass as file above), we hit "Argument list too long"
      # no clue why
      actualBuildPhase = pkgs.lib.concatMapStringsSep "\n\n" (
        cargoToml:
        let
          features = builtins.attrNames (builtins.removeAttrs (cargoToml.features or { }) [ "default" ]);
          subsets =
            xs: n:
            if n == 0 then
              [ [ ] ]
            else if xs == [ ] then
              [ ]
            else
              let
                x = builtins.head xs;
                xs' = builtins.tail xs;
              in
              (map (ys: [ x ] ++ ys) (subsets xs' (n - 1))) ++ (subsets xs' n);
          allFeatureCombinations = pkgs.lib.concatLists (
            builtins.genList (subsets features) (dbg (builtins.length (dbg features) + 1))
          );
        in
        if cargoToml.package.name == "protos" then
          "cargo clippy -p protos --all-features --tests -- -Dwarnings"
        else if features == [ ] then
          "cargo clippy -p ${cargoToml.package.name} --no-default-features --tests -- -Dwarnings"
        else
          pkgs.lib.concatMapStringsSep "\n"
            (
              features:
              "cargo clippy -p ${cargoToml.package.name} --no-default-features ${pkgs.lib.optionalString (features != [ ]) "-F${pkgs.lib.concatMapStringsSep "," (f: f) features}"} --tests -- -Dwarnings"
            )
            allFeatureCombinations
      );
      doInstallCargoArtifacts = false;
    }
  );
}
