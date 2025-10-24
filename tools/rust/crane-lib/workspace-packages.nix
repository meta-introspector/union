{ pkgs, lib', crane, cargoWorkspaceAttrs, cargoArtifacts, workspaceCargoVendorDir, inputs, mkCrane, ... }:

{
  rust-lib = pkgs.mkRootDrv "rust-lib" {
    inherit mkCrane; # mkCrane will be passed from the main crane.nix
  };
  # cleanCargoLock = writeTOML "Cargo.lock" (cleanCargoLock [ "ibc-union" ]);
  # cleanCargoLock = writeTOML "Cargo.lock" (
  #   cleanCargoLock (
  #     builtins.attrNames (
  #       ((crateCargoToml "cosmwasm/ibc-union/core").dependencies or { })
  #       // ((crateCargoToml "cosmwasm/ibc-union/core").build-dependencies or { })
  #       // (lib.optionalAttrs false (crateCargoToml "cosmwasm/ibc-union/core").dev-dependencies or { })
  #     )
  #   )
  # );
  # getAllDeps = dbg (getAllDeps [ "cosmwasm/ibc-union/core" ]);
  # getDependency = dbg (
  #   getCargoLockPackageEntry "static_assertions 1.1.0 (registry+https://github.com/rust-lang/crates.io-index)"
  # );
  # normalizedCargoLock = writeJSON "normalized-Cargo.lock.json" normalizedCargoLock;
  check-all-workspace-members-individually = pkgs.writeShellApplication {
    name = "check-all-workspace-members-individually";
    text = ''
      cargo metadata --no-deps | jq '.workspace_members[]' -r | xargs -I{} cargo check -p {}
    '';
  };

  rust-docs = crane.lib.cargoDoc (
    cargoWorkspaceAttrs
    // {
      pname = "rust-docs";
      version = "0.0.0";
      src = crane.cargoWorkspaceSrc;
      cargoVendorDir = workspaceCargoVendorDir;
      inherit cargoArtifacts;
      cargoDocExtraArgs = "--workspace";
      RUSTDOCFLAGS = "-Z unstable-options --enable-index-page";
    }
  );

  # FIXME: currently ICE, https://github.com/unionlabs/union/actions/runs/8882618404/job/24387814904
  # packages.rust-coverage =
  #   let
  #     crane.lib = crane.lib.${system}.overrideToolchain rust.toolchains.dev;
  #   in
  #   crane.lib.cargoLlvmCov {
  #     pname = "workspace-cargo-llvm-cov";
  #     version = "0.0.0";
  #     cargoLlvmCovExtraArgs = lib.concatStringsSep " " [
  #       "--workspace"
  #       "--html"
  #       "--output-dir=$out"
  #       "--ignore-filename-regex='((nix/store)|(generated))/.+'"
  #       "--exclude=parse-wasm-client-type"
  #       "--exclude=protos"
  #       "--exclude=contracts"
  #       "--exclude=unionvisor" # TODO: Figure out why unionvisor tests are flakey
  #       "--exclude=tidy"
  #       "--exclude=generate-rust-sol-bindings"
  #       "--exclude=ensure-blocks"
  #       "--hide-instantiations"
  #     ];
  #     SQLX_OFFLINE = true;
  #     cargoArtifacts = craneLib.buildDepsOnly {
  #       pname = "workspace-build-deps-only";
  #       version = "0.0.0";
  #       cargoExtraArgs = "--locked";
  #       doCheck = false;

  #       buildInputs = [ pkgs.pkg-config pkgs.openssl ] ++ (
  #         lib.optionals pkgs.stdenv.isDarwin [ pkgs.darwin.apple_sdk.frameworks.Security ]
  #       );
  #       src = cargoWorkspaceSrc;
  #     };
  #     preBuild = ''
  #       cp --no-preserve=mode ${self'.packages.uniond}/bin/uniond $(pwd)/unionvisor/src/testdata/test_init_cmd/bundle/bins/genesis
  #       echo 'patching testdata'
  #       patchShebangs $(pwd)/unionvisor/src/testdata
  #     '';
  #     ICS23_TEST_SUITE_DATA_DIR = "${inputs.ics23}/testdata";
  #     ETHEREUM_CONSENSUS_SPECS_DIR = "${inputs.ethereum-consensus-specs}";

  #     buildInputs = [ pkgs.pkg-config pkgs.openssl ] ++ (
  #       lib.optionals pkgs.stdenv.isDarwin [ pkgs.darwin.apple_sdk.frameworks.Security ]
  #     );
  #     src = cargoWorkspaceSrc;
  #   };
}
