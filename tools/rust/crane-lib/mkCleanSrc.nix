{ pkgs
, lib' = lib;
fs,
mkRootPaths,
isListOf,
writeTOML,
readMemberCargoTomls,
...
}:

let
  # build a clean source for the specified workspace members and any extra includes.
  mkCleanSrc =
    {
      # [path]
      workspaceMembers
    , # [path]
      extraIncludes
    , # path | derivation
      cargoToml
    , # path | derivation
      cargoLock
    , # bool
      dontRemoveDevDeps ? false
    , root
    , # Passed from mkCrane
    }:
      assert isListOf builtins.isString workspaceMembers;
      assert isListOf builtins.isString extraIncludes;
      let
        filteredSrc = fs.toSource {
          inherit root;
          fileset =
            fs.union
              # unconditionally include...
              (fs.unions (lib'.flatten [ (mkRootPaths extraIncludes) ]))
              # ...and include rust source of workspace deps
              (
                fs.difference
                  (fs.intersection (fs.unions (mkRootPaths workspaceMembers)) (
                    fs.fileFilter (file: (builtins.any file.hasExt [ "rs" ])) root
                  ))
                  (
                    if dontRemoveDevDeps then
                      fs.unions [ ]
                    else
                      (fs.unions (
                        (map fs.maybeMissing (mkRootPaths (map (member: "${member}/tests") workspaceMembers)))
                        ++ (map fs.maybeMissing (mkRootPaths (map (member: "${member}/examples") workspaceMembers)))
                      ))
                  )
              );
          in
          pkgs.stdenv.mkDerivation {
          name = "clean-workspace-source";
          src = filteredSrc;
          buildInputs = [ ];
          buildPhase = ''
            cp ${cargoLock} ./Cargo.lock
            cp ${cargoToml} ./Cargo.toml

            ${builtins.concatStringsSep "\n\n" (
              lib'.mapAttrsToList (
                path:
                cargoToml:
                let
                  cargoTomlPath = writeTOML "Cargo.toml" (
                    builtins.removeAttrs cargoToml (lib'.optionals (!dontRemoveDevDeps) [ "dev-dependencies" ])
                  );
                in
                "cp ${cargoTomlPath} ./${path}/Cargo.toml"
              ) (readMemberCargoTomls workspaceMembers)
            )}

            cp -r . $out
          '';
        };
      in
      {
        inherit mkCleanSrc;
      }
