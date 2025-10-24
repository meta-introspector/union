{ pkgs, lib, args, root, ... }:

let
  fs = pkgs.lib.fileset;

  writeTOML = (pkgs.formats.toml { }).generate;

  # clean up the lib namespace for what we actually need
  lib' = lib // {
    inherit (lib.attrsets) nameValuePair attrByPath;
    inherit (lib.trivial) importTOML concat;
  };

  # check whether a list is a list of a specific type.
  #
  # sig :: (any -> bool) -> [any] -> bool
  isListOf = pred: list: builtins.isList list && builtins.all pred list;

  # converts a path relative to the root of the repository to an absolute path that can be used with the fileset api.
  #
  # string -> path
  mkRootPath = path: root + /${path};

  # map a list of paths relative to the root of the repository to absolute paths that can be used with the fileset api.
  #
  # [string] -> [path]
  mkRootPaths = map mkRootPath;

in
{
  inherit fs writeTOML lib' isListOf mkRootPath mkRootPaths;
}
