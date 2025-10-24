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