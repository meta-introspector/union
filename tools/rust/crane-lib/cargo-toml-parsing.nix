{ pkgs, lib', root, ... }:

let
  # get the crane metadata out of the Cargo.toml. returns an empty attrset if the table is not present.
  #
  # [package.metadata.crane]
  # test-include = ["path3", "path4"]
  #
  # sig :: attrs -> attrs;
  getCraneMetadata =
    toml:
      assert builtins.isAttrs toml;
      lib'.attrByPath [
        "package"
        "metadata"
        "crane"
      ]
        { }
        toml;

  # get any extra test includes specified in the crane metadata.
  #
  # [package.metadata.crane]
  # test-include = ["path3", "path4"]
  getExtraIncludes =
    memberCargoTomls:
    lib'.unique (
      lib'.flatten (
        map (toml: (getCraneMetadata toml).test-include or [ ]) (builtins.attrValues memberCargoTomls)
      )
    );

  # get any includes specified in package.include, normalized to the repo root.
  #
  # [package]
  # include = [".sqlx", "README.md"]
  #
  # sig :: { string : attrs } -> [string]
  getIncludes =
    memberCargoTomls:
      assert builtins.isAttrs memberCargoTomls;
      lib'.unique (
        lib'.flatten (
          map
            (
              memberName:
              map (include: "${memberName}/${include}") (memberCargoTomls.${memberName}.package.include or [ ])
            )
            (builtins.attrNames memberCargoTomls)
        )
      );

  # nix doesn't cache calls to b.readFile (which importTOML calls internally), so we cache the cargo tomls here
  # this saves ~2-3 minutes in evaluation time
  #
  # sig :: [string] -> attrs
  readMemberCargoTomls =
    members:
    builtins.listToAttrs (
      map (dep: lib'.nameValuePair dep (lib'.importTOML "${root}/${dep}/Cargo.toml")) members
    );

  # read the Cargo.toml from the given crate directory into a nix value.
  #
  # sig :: string -> attrs
  crateCargoToml =
    dir:
      assert lib'.assertMsg (builtins.isString dir)
        "expected string, found ${builtins.typeOf dir} while trying to read Cargo.toml (stringified value: ${toString dir})";
      lib'.importTOML (root + /${dir}/Cargo.toml);

  # Cargo.toml of the workspace.
  #
  # sig :: string
  workspaceCargoToml = lib'.importTOML (root + "/Cargo.toml");

in
{
  inherit getCraneMetadata getExtraIncludes getIncludes readMemberCargoTomls crateCargoToml workspaceCargoToml;
}
