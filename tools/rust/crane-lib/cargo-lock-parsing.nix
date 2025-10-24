{ pkgs, lib', root, ... }:

let
  # TODO: Assert version = 4;
  normalizedCargoLock = builtins.foldl' (acc: p: lib'.recursiveUpdate acc p) { } (
    map
      (package: {
        ${package.name} = {
          ${package.version} =
            package
            // (lib'.optionalAttrs (package ? source) (
              let
                splitSource = lib'.splitString "+" package.source;
                sourceType = builtins.head splitSource;
                sourceKey = # trim the commit ref if this is a git source
                  # TODO: figure out how this is actually defined to work in the Cargo.lock schema/spec
                  if sourceType == "git" then builtins.head (lib'.splitString "#" package.source) else package.source;
              in
              {
                __source__.${sourceKey} = package;
              }
            ));
        };
      })
      (lib'.importTOML (root + "/Cargo.lock")).package
  );

  # get a single package entry from the Cargo.lock.
  #
  # sig :: string -> attrs
  getCargoLockPackageEntry =
    depAndVersion:
    let
      split = lib'.splitString " " depAndVersion;
      depName = builtins.head split;
      specifiedVersion = builtins.elemAt split 1;
      specifiedSource = builtins.head (builtins.match "[(](.*)[)]" (builtins.elemAt split 2));
      fullDep = normalizedCargoLock.${depName};
    in
    builtins.removeAttrs
      (
        # dep name is just the dep name (no version or source)
        # this means that this dependency only exists once in the lockfile, and as such only one version subkey will exist
        if ((builtins.length split) == 1) then
          fullDep.${builtins.head (builtins.attrNames fullDep)}
        # dep name is the dep name and a version (no source)
        else if ((builtins.length split) == 2) then
          fullDep.${specifiedVersion}
        # dep name is the dep name, version, and source
        else if ((builtins.length split) == 3) then
          fullDep.${specifiedVersion}.__source__.${specifiedSource}
        else
          throw "???"
      ) [ "__source__" ];

  getAllPackageDependencies =
    packageName:
    let
      go =
        foundSoFar: packageName':
        let
          packageLockEntry = getCargoLockPackageEntry packageName';
          packageKey = packageName';
          namedDep = {
            ${packageKey} = packageLockEntry;
          };
        in
        if builtins.hasAttr packageKey foundSoFar then
          foundSoFar
        else if packageLockEntry ? dependencies then
          (builtins.foldl' go (namedDep // foundSoFar)) packageLockEntry.dependencies
        else
          foundSoFar // namedDep;
    in
    go { } packageName;

  cleanCargoLock = packages: {
    version = 4;
    package = lib'.unique (
      lib'.flatten (map (x: builtins.attrValues (getAllPackageDependencies x)) packages)
    );
  };

in
{
  inherit normalizedCargoLock getCargoLockPackageEntry getAllPackageDependencies cleanCargoLock;
}
