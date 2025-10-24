# Reusable Rust Dependencies for Nix

This directory contains Nix files designed to provide reusable definitions for common Rust-related dependencies and configurations.

## `openssl-deps.nix`

This file provides a granular, reusable module specifically for integrating OpenSSL dependencies into your Rust projects. It encapsulates the necessary `buildInputs` and `PKG_CONFIG_PATH` configuration for OpenSSL.

### Usage:

To use `openssl-deps.nix` in your Nix flake or derivation:

1.  **Import the file:**
    ```nix
    # In your flake.nix or a module
    let
      # Assuming 'pkgs' and 'lib' are in scope from your Nixpkgs import
      opensslDeps = import ./tools/rust/openssl-deps.nix { inherit pkgs lib; };
      inherit (opensslDeps) opensslBuildInputs opensslPkgConfigPath;
    in
    # ...
    ```

2.  **Integrate into `buildInputs`:**
    Add `opensslBuildInputs` to your derivation's `buildInputs`.

    **Example:**
    ```nix
    buildInputs = opensslBuildInputs ++ [
      # other build inputs specific to your project
      pkgs.some-other-dependency
    ];
    ```

3.  **Set `PKG_CONFIG_PATH`:**
    Use `opensslPkgConfigPath` for setting the `PKG_CONFIG_PATH` environment variable.

    **Example:**
    ```nix
    PKG_CONFIG_PATH = opensslPkgConfigPath;
    ```

---

## `common-rust-deps.nix` (Updated)

This file exports an attribute set containing common build inputs and environment variables related to `openssl` and `pkg-config`, now leveraging `openssl-deps.nix` for better modularity.

### Usage:

To use `common-rust-deps.nix` in your Nix flake or derivation:

1.  **Import the file:**
    ```nix
    # In your flake.nix or a module
    let
      # Assuming 'pkgs' and 'lib' are in scope from your Nixpkgs import
      commonRustDeps = import ./tools/rust/common-rust-deps.nix { inherit pkgs lib; };
      inherit (commonRustDeps) commonBuildInputs pkgConfigPath;
    in
    # ...
    ```

2.  **Integrate into `buildInputs`:**
    Replace explicit `pkgs.pkg-config`, `pkgs.openssl`, and the conditional Darwin security framework with `commonBuildInputs`.

    **Example:**
    ```nix
    buildInputs = commonBuildInputs ++ [
      # other build inputs specific to your project
      pkgs.some-other-dependency
    ];
    ```

3.  **Set `PKG_CONFIG_PATH`:**
    Use `pkgConfigPath` for setting the `PKG_CONFIG_PATH` environment variable.

    **Example:**
    ```nix
    PKG_CONFIG_PATH = pkgConfigPath;
    ```

This approach centralizes the management of these common dependencies, making your Nix expressions cleaner and more maintainable across different Rust projects.

---

## `crane-lattice.nix`

This file provides a refactored and modularized version of the original `crane.nix` functionality, composed from smaller, logically grouped Nix modules. It aims to improve readability, maintainability, and reusability of the Rust build definitions.

### Purpose:

`crane-lattice.nix` defines a `mkCraneLattice` function that encapsulates the logic for building Rust projects within a Nix environment, similar to the original `crane.nix`, but built upon a "lattice" of smaller modules.

### Usage:

To use `crane-lattice.nix` in your Nix flake:

1.  **Import `crane-lattice.nix`:**
    You would typically import this file into your main `flake.nix` or another module that needs to build Rust projects.

    ```nix
    # In your main flake.nix
    inputs = {
      # ... other inputs
      craneLattice = {
        url = "./vendor/nix/union/tools/rust/crane-lattice.nix"; # Adjust path as needed
        inputs.nixpkgs.follows = "nixpkgs";
        inputs.crane.follows = "crane"; # Assuming crane is also an input
        inputs.rust-overlay.follows = "rust-overlay"; # Assuming rust-overlay is also an input
        # ... other inputs required by crane-lattice.nix
      };
    };

    outputs = { self, nixpkgs, craneLattice, ... }: {
      # ...
      perSystem = { pkgs, lib, system, ... }:
        let
          # Instantiate the craneLattice module
          crane = craneLattice.perSystem {
            inherit pkgs lib system;
            # Pass other necessary arguments like rust, dbg, gitRev, etc.
            # These would typically come from the perSystem scope of your main flake.
            rust = inputs.rust-overlay.packages.${system}.rust-bin.stable.latest.default; # Example
            dbg = lib.debug.trace; # Example
            gitRev = self.rev or "dirty"; # Example
            inputs = {
              inherit self nixpkgs craneLattice;
              crane = inputs.crane;
              # ... other inputs that crane-lattice needs
            };
          };
        in
        {
          # Now you can use the 'crane' object provided by crane-lattice
          # For example, to access checks or packages:
          checks = crane.checks;
          packages = crane.packages;
          devShells.default = pkgs.mkShell {
            buildInputs = [ crane.packages.rust-lib ]; # Example
          };
        };
    };
    ```

2.  **Access Composed Functionality:**
    The `crane` object returned by `craneLattice.perSystem` will expose the `cargoWorkspaceSrc`, `buildWorkspaceMember`, `buildWasmContract`, `allCargoTomls`, `craneLib`, `workspaceCargoVendorDir`, `cargoWorkspaceAttrs`, and `cargoArtifacts` attributes, along with the `checks` and `packages` defined in the respective modules.

This modular structure makes it easier to understand, test, and maintain the complex Rust build logic.
