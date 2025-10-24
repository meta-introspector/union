{ lib', crateCargoToml, workspaceCargoToml, ... }:

let
  # gets all the local (i.e. path) dependencies for a crate, recursively.
  #
  # note that to make this easier, we define all local dependencies as workspace dependencies.
  #
  # sig :: [string] -> bool -> [string]
  getMemberDeps =
    dirs: dontRemoveDevDeps:
    let
      go =
        dir': foundSoFar:
        let
          dirCargoToml = crateCargoToml dir';
        in
        lib'.pipe
          (
            dirCargoToml.dependencies
            // (lib'.optionalAttrs dontRemoveDevDeps dirCargoToml.dev-dependencies or { })
            // dirCargoToml.build-dependencies or { }
          )
          [
            (lib'.filterAttrs (
              dependency: value:
              # ...and dep is a workspace dependency...
              (value.workspace or false)
              # ...and that workspace dependency is a path dependency...
              && (builtins.hasAttr "path" workspaceCargoToml.workspace.dependencies.${dependency})
              # ...and that workspace dependency has not been found yet (to prevent infinite recursion)
              && !(builtins.elem workspaceCargoToml.workspace.dependencies.${dependency}.path foundSoFar)
            ))
            (lib'.mapAttrsToList (
              name: _value:
              let
                inherit (workspaceCargoToml.workspace.dependencies.${name}) path;
              in
              (go path (lib'.unique (foundSoFar ++ [ path ]))) ++ [ path ]
            ))
            (lib'.concat [ dir' ])
            lib'.flatten
            lib'.unique
          ];
    in
    lib'.unique (lib'.flatten (builtins.map (dir: go dir [ ]) dirs));

  # gets all the dependencies for a crate, recursively.
  #
  # sig :: [string] -> bool -> [string]
  getAllDeps =
    dirs: dontRemoveDevDeps:
    lib'.pipe (getMemberDeps dirs dontRemoveDevDeps) [
      (map (
        path:
        ((crateCargoToml path).dependencies or { })
        // (lib'.optionalAttrs dontRemoveDevDeps (crateCargoToml path).dev-dependencies or { })
        // ((crateCargoToml path).build-dependencies or { })
      ))
      (builtins.foldl' lib'.recursiveUpdate { })
    ];

in
{
  inherit getMemberDeps getAllDeps;
}
