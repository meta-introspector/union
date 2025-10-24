{ pkgs
, lib'
, rust
, inputs
, craneLib
, dbg
, gitRev
, isListOf
, crateCargoToml
, workspaceCargoToml
, getMemberDeps
, getAllDeps
, cleanCargoLock
, writeTOML
, readMemberCargoTomls
, mkCleanSrc
, getIncludes
, getExtraIncludes
, # <--- Added these
  ...
}:

let
  # sig :: string -> attrs -> drv
  buildWorkspaceMember =
    # the directory that contains the Cargo.toml and src/ for the crate,
    # relative to the repository root, or a list of multiple crates.
    crateDirFromRoot:
    {
      # a suffix to add to the package name.
      pnameSuffix ? ""
    , # the pname to use for this derivation if building multiple packages.
      pname ? null
    , # the version to use for this derivation if building multiple packages.
      version ? null
    , # extra args to be passed to cargo build.
      cargoBuildExtraArgs ? ""
    , # if set to a string, the crate will be built for the specified target and will
      # rebuild the std library. incompatible with `cargoBuildRustToolchain`.
      buildStdTarget ? null
    , # update the toolchain that will be used for cargo build. defaults to
      # rust.toolchains.nightly if not set. incompatible with `buildStdTarget`.
      cargoBuildRustToolchain ? null
    , # rustflags to be passed to cargo build.
      rustflags ? ""
    , # checkPhase to be passed to the cargo build derivation.
      cargoBuildCheckPhase ? null
    , # installPhase to be passed to the cargo build derivation.
      cargoBuildInstallPhase ? null
    , # standard postBuild phase.
      postBuild ? null
    , # standard postInstall phase.
      postInstall ? null
    , # extra environment variables to pass to the derivation.
      extraEnv ? { }
    , # extra environment variables to pass to the derivation, only for crane.buildPackage.
      extraBuildEnv ? { }
    , extraBuildInputs ? [ ]
    , extraNativeBuildInputs ? [ ]
    , # this builder will by default remove dev-dependencies from the Cargo.toml of all crates in the filtered source of the packages being built. set this to true to disable this behaviour.
      dontRemoveDevDeps ? false
    , # the root Cargo.toml may require patching when building certain packages in the monorepo. this hook can be used to arbitrarily modify the patched Cargo.toml before writing it into the source root derivation.
      rootCargoTomlHook ? x: x
    , root
    , # Passed from mkCrane
    }:
      assert builtins.isAttrs extraEnv;
      assert lib'.assertMsg
        (
          (buildStdTarget != null -> cargoBuildRustToolchain == null)
          && (cargoBuildRustToolchain != null -> buildStdTarget == null)
        )
        "cannot set both buildStdTarget (${toString buildStdTarget}) and cargoBuildRustToolchain (${toString cargoBuildRustToolchain})";
      let
        pnameSuffix' = pnameSuffix;

        # normalize the crate info passed in, such that we can support both single and multiple packages with the same attribute
        processedCrateInfo =
          if (builtins.isList crateDirFromRoot) then
            assert isListOf builtins.isString crateDirFromRoot;
            {
              crateDirsFromRoot' = crateDirFromRoot;
              pname' =
                assert builtins.isString pname;
                pname;
              version' =
                assert builtins.isString version;
                version;
            }
          else if (builtins.isString crateDirFromRoot) then
            let
              cargoToml = (crateCargoToml crateDirFromRoot).package;
            in
            {
              crateDirsFromRoot' = [ crateDirFromRoot ];
              version' = cargoToml.version;
              pname' = cargoToml.name;
            }
          else
            abort "expected crateDirFromRoot to be a string or a list of strings, but it was a ${builtins.typeOf crateDirFromRoot}: ${toString crateDirFromRoot}";

        inherit (processedCrateInfo)
          crateDirsFromRoot'
          pname'
          version'
          ;

        # the rust toolchain that will be used to build the crate.
        # if build-std, use either the provided target or the default nightly toolchain. otherwise, just use the passed in toolchain.
        # the assertions at the beginning of this function ensure that these branches are exhaustive.
        cargoBuildRustToolchain' =
          if (cargoBuildRustToolchain == null) then
            (
              if buildStdTarget == null then
                rust.toolchains.nightly
              else
                rust.mkBuildStdToolchain { targets = [ buildStdTarget ]; }
            )
          else
            cargoBuildRustToolchain;

        cargoBuild = craneLib.overrideToolchain cargoBuildRustToolchain';

        memberDepsForCrate = getMemberDeps crateDirsFromRoot' dontRemoveDevDeps;
        memberDepsForCrateCargoTomls = readMemberCargoTomls memberDepsForCrate;

        patchedCargoLock = cleanCargoLock (map (dir: (crateCargoToml dir).package.name) crateDirsFromRoot');

        allDepsForCrate = getAllDeps memberDepsForCrate dontRemoveDevDeps;

        patchedCargoToml = {
          workspace = workspaceCargoToml.workspace // {
            members = memberDepsForCrate;
            dependencies = lib'.filterAttrs
              (
                dep: _: builtins.hasAttr dep allDepsForCrate
              )
              workspaceCargoToml.workspace.dependencies;
          };
          # only patch dependencies this crate actually depends on, since anything not in the lockfile will not be vendored by crane
          patch =
            if builtins.hasAttr "patch" workspaceCargoToml then
              workspaceCargoToml.patch
              // {
                crates-io = lib'.filterAttrs
                  (
                    depName: _patch: builtins.any (lockPackage: lockPackage.name == depName) patchedCargoLock.package
                  )
                  workspaceCargoToml.patch.crates-io;
              }
            else
              { };
        };

        # patch the workspace Cargo.toml and Cargo.lock to only contain the local dependencies required to build this crate
        crateRepoSource = mkCleanSrc {
          inherit dontRemoveDevDeps root;
          workspaceMembers = memberDepsForCrate;
          extraIncludes =
            (getIncludes memberDepsForCrateCargoTomls) ++ (getExtraIncludes memberDepsForCrateCargoTomls); # Corrected line
          cargoToml = writeTOML "Cargo.toml" (rootCargoTomlHook patchedCargoToml);
          cargoLock = writeTOML "Cargo.lock" patchedCargoLock;
        };

        # build the package.
        #
        # sig :: bool -> attrs
        builder =
          release:
          let
            packageFilterArgs = lib'.concatMapStringsSep " "
              (
                dir: "-p ${(crateCargoToml dir).package.name}"
              )
              crateDirsFromRoot';

            crateAttrs = extraEnv // {
              pname = pname';
              version = version';

              dummySrc = craneLib.mkDummySrc {
                src = crateRepoSource;
              };

              # defaults to "--all-targets" otherwise, which breaks some stuff
              cargoCheckExtraArgs = "";

              buildInputs =
                [
                  pkgs.pkg-config
                  pkgs.openssl
                ]
                ++ (lib'.optionals pkgs.stdenv.isDarwin [ pkgs.darwin.apple_sdk.frameworks.Security ])
                ++ extraBuildInputs;

              # [ pkgs.breakpointHook ] ++ 
              nativeBuildInputs = extraNativeBuildInputs;

              cargoVendorDir = craneLib.vendorMultipleCargoDeps {
                inherit (craneLib.findCargoFiles crateRepoSource) cargoConfigs;
                cargoLockList = lib'.optionalAttrs (buildStdTarget != null) [
                  ./rust-std-Cargo.lock
                ];
                cargoLockParsedList = [
                  patchedCargoLock
                ];
                overrideVendorGitCheckout =
                  ps: drv:
                  if lib'.any (p: (lib'.hasInfix "zhiburt/tabled" p.source)) ps then
                    drv.overrideAttrs
                      (_old: {
                        postPatch = ''
                          # broken symlink or something idk
                          # https://github.com/ipetkov/crane/issues/802
                          # https://github.com/zhiburt/tabled/issues/538
                          rm tabled/examples/show/LICENSE
                        '';
                      })
                  else
                  # Nothing to change, leave the derivations as is
                    drv;
              };

              PKG_CONFIG_PATH = "${pkgs.openssl.dev}/lib/pkgconfig";

              # RUST_MIN_STACK = 16777216; # ICE fix: maybe related to https://github.com/rust-lang/rust/issues/131419

              # we don't want to run cargo check or cargo test on this derivation since we do that in a separate package
              doCheck = false;

              pnameSuffix = pnameSuffix' + (lib'.optionalString release "-release");

              cargoExtraArgs =
                # REVIEW: Can -j1 only be specified for buildPackage and still get deterministic builds?
                "${lib'.optionalString release "-j1"} ${packageFilterArgs} ${cargoBuildExtraArgs}"
                  + (lib'.optionalString (buildStdTarget != null)
                  # the leading space is important here!
                  " -Z build-std=std,panic_abort -Z build-std-features=panic-immediate-abort --target ${buildStdTarget}"
                );
              RUSTFLAGS = rustflags;

              preBuild =
                (lib'.concatMapStringsSep "\n\n"
                  (dir: ''
                    if test -f ${dir}/src/main.rs; then
                      echo "extern crate embed_commit as _ ;" >> ${dir}/src/main.rs
                    else
                      echo "extern crate embed_commit as _ ;" >> ${dir}/src/lib.rs
                    fi
                  '')
                  crateDirsFromRoot')
                + lib'.optionalString release ''
                  echo "cargoVendorDir: ${crateAttrs.cargoVendorDir}"
                  echo "rustToolchain: ${cargoBuildRustToolchain'}"

                  # find ${crateAttrs.cargoVendorDir} -maxdepth 1 -xtype d | grep -v '^${crateAttrs.cargoVendorDir}$' | sed -E 's@(.+)@ --remap-path-prefix=\1=/@g'

                  export RUSTFLAGS="$RUSTFLAGS $(find ${crateAttrs.cargoVendorDir} -maxdepth 1 -xtype d | grep -v '^${crateAttrs.cargoVendorDir}$' | sed -E 's@(.+)@ --remap-path-prefix=\1=@g' | tr '\n' ' ')  --remap-path-prefix=${cargoBuildRustToolchain'}/lib/rustlib/src/rust/library/alloc/src/= --remap-path-prefix=${cargoBuildRustToolchain'}/lib/rustlib/src/rust/library/std/src/= --remap-path-prefix=${cargoBuildRustToolchain'}/lib/rustlib/src/rust/library/core/src/="

                  echo "$RUSTFLAGS"
                '';
            };

            cargoArtifacts = cargoBuild.buildDepsOnly crateAttrs;
          in

          (cargoBuild.buildPackage (
            extraBuildEnv
            // crateAttrs
            // {
              src = crateRepoSource;
              inherit cargoArtifacts;
            }
            // (lib'.optionalAttrs (builtins.length crateDirsFromRoot' == 1) {
              meta.mainProgram = pname';
            })
            // (lib'.optionalAttrs (cargoBuildInstallPhase != null) {
              installPhaseCommand = cargoBuildInstallPhase;
            })
            // (lib'.optionalAttrs (postBuild != null) {
              inherit postBuild;
            })
            // (lib'.optionalAttrs (postInstall != null) {
              inherit postInstall;
            })
            // (lib'.optionalAttrs (cargoBuildCheckPhase != null) {
              checkPhase = cargoBuildCheckPhase;
            })
            # for release builds, embed the git rev
            // (lib'.optionalAttrs release {
              GIT_REV = gitRev;
            })
          )).overrideAttrs
            (
              old:
              {
                passthru = (old.passthru or { }) // {
                  inherit release;
                  craneAttrs = crateAttrs // {
                    src = crateRepoSource;
                    inherit cargoArtifacts;
                  };
                };
              }
              // old
            );
      in
      {
        "${pname'}${pnameSuffix'}" = (builder false) // {
          release = builder true;
        };
      };
in
{
  inherit buildWorkspaceMember;
}
