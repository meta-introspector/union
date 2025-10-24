{ inputs
, pkgs
, lib'
, craneLib
, mkCrane
, mkCleanSrc
, getIncludes
, getExtraIncludes
, readMemberCargoTomls
, workspaceCargoToml
, gitRev
, buildWorkspaceMember
, crateCargoToml
, rust
, dbg
, ...
}: # Added buildWorkspaceMember, crateCargoToml, rust, dbg

let
  allCargoTomls = builtins.listToAttrs (
    map
      (
        dep: lib'.nameValuePair dep (readMemberCargoTomls [ dep ])
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
      buildWorkspaceMember# This will be passed from mkCrane
      crateCargoToml# This will be passed from mkCrane
      pkgs
      lib'
      rust# This will be passed from mkCrane
      craneLib
      dbg# This will be passed from mkCrane
      gitRev
      ;
  };

  crane = mkCrane {
    root = inputs.self; # Assuming inputs.self is the root of the repo
    inherit gitRev;
  };

  workspaceCargoVendorDir = crane.lib.vendorCargoDeps {
    src = crane.cargoWorkspaceSrc;
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
    src = crane.cargoWorkspaceSrc;

    # unionvisor is tested individually, and mpc* crates attempt to link to galoisd (and don't have any tests anyways).
    cargoTestExtraArgs = "--workspace --all-features --exclude 'mpc*' --exclude unionvisor --exclude union-test --no-fail-fast";
    cargoClippyExtraArgs = "--workspace --tests --all-features -- -Dwarnings";

    CARGO_PROFILE = "dev";
    SQLX_OFFLINE = true;
    PKG_CONFIG_PATH = "${pkgs.openssl.dev}/lib/pkgconfig";
    LIBCLANG_PATH = "${pkgs.llvmPackages_14.libclang.lib}/lib";
    ICS23_TEST_SUITE_DATA_DIR = "${inputs.ics23}/testdata";

    buildInputs = [
      pkgs.pkg-config
      pkgs.perl
      pkgs.openssl
      pkgs.protobuf
      pkgs.perl
      pkgs.gnumake
      pkgs.systemd
    ] ++ (pkgs.lib.optionals pkgs.stdenv.isDarwin [ pkgs.darwin.apple_sdk.frameworks.Security ]);
    nativeBuildInputs = [
      pkgs.clang
    ];
    cargoVendorDir = workspaceCargoVendorDir;
  };
  cargoArtifacts = crane.lib.buildDepsOnly cargoWorkspaceAttrs;

in
{
  inherit allCargoTomls cargoWorkspaceSrc buildWasmContract crane workspaceCargoVendorDir cargoWorkspaceAttrs cargoArtifacts;
}
