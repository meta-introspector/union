{ inputs
, pkgs
, lib'
, craneLib
, mkCleanSrc
, getIncludes
, getExtraIncludes
, crateCargoToml
, workspaceCargoToml
, gitRev
, buildWorkspaceMember
, rust
, dbg
, ...
}:

let
  allCargoTomls = builtins.listToAttrs (
    map
      (
        dep: lib'.nameValuePair dep (crateCargoToml dep) # Corrected: use crateCargoToml directly
      )
      workspaceCargoToml.workspace.members
  );

  cargoWorkspaceSrc = mkCleanSrc {
    workspaceMembers = workspaceCargoToml.workspace.members;
    extraIncludes = (getIncludes allCargoTomls) ++ (getExtraIncludes allCargoTomls);
    cargoToml = /${inputs.self}/Cargo.toml; # Assuming inputs.self is the root of the repo
    cargoLock = /${inputs.self}/Cargo.lock; # Assuming inputs.self is the root of the repo
    dontRemoveDevDeps = true;
    root = inputs.self; # Pass root to mkCleanSrc
  };

  buildWasmContract = import ../buildWasmContract.nix {
    # Relative path to original
    inherit
      buildWorkspaceMember
      crateCargoToml
      pkgs
      lib'
      rust
      craneLib
      dbg
      gitRev
      ;
  };

in
{
  inherit allCargoTomls cargoWorkspaceSrc buildWasmContract;
}
