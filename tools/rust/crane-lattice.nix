# tools/rust/crane-lattice.nix
{ inputs
, ...
}:
{
  perSystem =
    args@{ pkgs
    , rust
    , dbg
    , gitRev
    , lib
    , # The original lib from args
      ...
    }:
    let
      # Import common rust dependencies
      commonRustDeps = import ./common-rust-deps.nix { inherit pkgs lib; };
      inherit (commonRustDeps) commonBuildInputs pkgConfigPath;

      # Import all the smaller modules, passing necessary arguments
      # Note: 'root' will be passed to mkCraneLattice, not directly here
      utils = import ./crane-lib/utils.nix { inherit pkgs args; lib = lib; root = null; };
      inherit (utils) fs writeTOML lib' isListOf mkRootPath mkRootPaths;

      cargoTomlParsing = import ./crane-lib/cargo-toml-parsing.nix { inherit pkgs lib' root; };
      inherit (cargoTomlParsing) getCraneMetadata getExtraIncludes getIncludes readMemberCargoTomls crateCargoToml workspaceCargoToml;

      cargoLockParsing = import ./crane-lib/cargo-lock-parsing.nix { inherit pkgs lib' root; };
      inherit (cargoLockParsing) normalizedCargoLock getCargoLockPackageEntry getAllPackageDependencies cleanCargoLock;

      dependencyResolution = import ./crane-lib/dependency-resolution.nix { inherit lib' crateCargoToml workspaceCargoToml; };
      inherit (dependencyResolution) getMemberDeps getAllDeps;

      mkCleanSrcModule = import ./crane-lib/mkCleanSrc.nix { inherit pkgs lib' fs mkRootPaths isListOf writeTOML readMemberCargoTomls; };
      mkCleanSrc = mkCleanSrcModule.mkCleanSrc;

      buildWorkspaceMemberModule = import ./crane-lib/buildWorkspaceMember.nix {
        inherit pkgs lib' rust inputs craneLib dbg gitRev
          isListOf crateCargoToml workspaceCargoToml getMemberDeps getAllDeps
          cleanCargoLock writeTOML readMemberCargoTomls mkCleanSrc
          getIncludes getExtraIncludes;
        root = null; # root will be passed to mkCraneLattice
      };
      buildWorkspaceMember = buildWorkspaceMemberModule.buildWorkspaceMember;

      # Define mkCraneLattice function
      mkCraneLattice =
        { root
        , gitRev
        ,
        }:
        let
          craneLib = (inputs.crane.mkLib pkgs).overrideToolchain (_: rust.toolchains.nightly);

          workspaceHelpers = import ./crane-lib/workspace-helpers.nix {
            inherit inputs pkgs lib' craneLib mkCleanSrc
              getIncludes getExtraIncludes crateCargoToml
              workspaceCargoToml gitRev buildWorkspaceMember rust dbg;
            root = root;
          };
          inherit (workspaceHelpers) allCargoTomls cargoWorkspaceSrc buildWasmContract;

          workspaceCargoVendorDir = craneLib.vendorCargoDeps {
            src = cargoWorkspaceSrc;
            overrideVendorGitCheckout =
              ps: drv:
              if pkgs.lib.any (p: (pkgs.lib.hasInfix "zhiburt/tabled" p.source)) ps then
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

          cargoWorkspaceAttrs = {
            pname = "cargo-workspace";
            version = "0.0.0";
            src = cargoWorkspaceSrc;

            # unionvisor is tested individually, and mpc* crates attempt to link to galoisd (and don't have any tests anyways).
            cargoTestExtraArgs = "--workspace --all-features --exclude 'mpc*' --exclude unionvisor --exclude union-test --no-fail-fast";
            cargoClippyExtraArgs = "--workspace --tests --all-features -- -Dwarnings";

            CARGO_PROFILE = "dev";
            SQLX_OFFLINE = true;
            PKG_CONFIG_PATH = pkgConfigPath; # Using common-rust-deps
            LIBCLANG_PATH = "${pkgs.llvmPackages_14.libclang.lib}/lib";
            ICS23_TEST_SUITE_DATA_DIR = "${inputs.ics23}/testdata";

            buildInputs = commonBuildInputs ++ [
              pkgs.perl
              pkgs.protobuf
              pkgs.perl
              pkgs.gnumake
              pkgs.systemd
            ]; # Using common-rust-deps
            nativeBuildInputs = [
              pkgs.clang
            ];
            cargoVendorDir = workspaceCargoVendorDir;
          };
          cargoArtifacts = craneLib.buildDepsOnly cargoWorkspaceAttrs;

        in
        {
          inherit
            cargoWorkspaceSrc
            buildWorkspaceMember
            buildWasmContract
            allCargoTomls
            craneLib# Export craneLib as well
            workspaceCargoVendorDir
            cargoWorkspaceAttrs
            cargoArtifacts
            ;
          lib = craneLib; # This seems redundant with craneLib above, but matches original
        };

      crane = mkCraneLattice {
        root = ../../.; # Assuming this is the correct root for the original crane.nix context
        inherit (args) gitRev;
      };

    in
    {
      _module.args = {
        inherit crane mkCraneLattice;
      };

      checks = import ./crane-lib/workspace-checks.nix {
        inherit pkgs lib' crane cargoWorkspaceAttrs cargoArtifacts allCargoTomls dbg;
      };

      packages = import ./crane-lib/workspace-packages.nix {
        inherit pkgs lib' crane cargoWorkspaceAttrs cargoArtifacts workspaceCargoVendorDir inputs mkCraneLattice;
      };
    };
}
