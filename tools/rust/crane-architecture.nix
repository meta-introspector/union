# tools/rust/crane-architecture.nix
{ inputs, ... }:
{
  perSystem =
    args@{ pkgs
    , lib
    , system
    , rust
    , dbg
    , gitRev
    , ...
    }:
    let
      # 1. Define the 8 layers and their associated prime chunks (primorials)
      primeLayers = [ 2 3 5 7 11 13 17 19 ];

      layerVibes = {
        "2" = {
          name = "Duality / Foundation";
          modules = [
            ./crane-lib/utils.nix
            ./common-rust-deps.nix
          ];
          description = "Represents binary distinctions and input/output relationships, serving as the foundational bit of creation.";
        };
        "3" = {
          name = "Structure / Completeness";
          modules = [
            ./crane-lib/cargo-toml-parsing.nix
          ];
          description = "Pertains to triadic structures, internal coherence, and the imposition of order.";
        };
        "5" = {
          name = "Form / Pattern Recognition";
          modules = [
            ./crane-lib/cargo-lock-parsing.nix
          ];
          description = "Defines form, external shape, and the discernment of specific patterns.";
        };
        "7" = {
          name = "Insight / Guidance / Transformation";
          modules = [
            ./crane-lib/dependency-resolution.nix
          ];
          description = "Relates to analytical processes, knowledge extraction, guidance, and handling transformations.";
        };
        "11" = {
          name = "Interaction / Dynamic Flow";
          modules = [
            ./crane-lib/mkCleanSrc.nix
          ];
          description = "Represents dynamic energy, live engagement, and runtime state management.";
        };
        "13" = {
          name = "Transformation / Challenge / Verification";
          modules = [
            ./crane-lib/buildWorkspaceMember.nix
          ];
          description = "Represents challenge, verification, and the transformation of unformed potential (Concurrency Orchestration).";
        };
        "17" = {
          name = "Refinement / Integration";
          modules = [
            ./crane-lib/workspace-helpers.nix
          ];
          description = "Represents integration of complex systems and recognizing profound underlying system patterns.";
        };
        "19" = {
          name = "Manifestation / Core Being";
          modules = [
            ./crane-lib/workspace-checks.nix
            ./crane-lib/workspace-packages.nix
          ];
          description = "Represents the maximum single-level complexity and the system's manifested essence.";
        };
      };

      # Function to compose the crane-lattice based on the architectural definition
      mkArchitecturalCrane =
        { root
        , gitRev
        , # Pass all necessary arguments for crane-lattice.nix
          inherit inputs pkgs lib system args rust dbg;
        }:
        let
          # Import crane-lattice.nix
          craneLattice = import ./crane-lattice.nix { inherit inputs; };

          # Instantiate the crane-lattice module
          # This will effectively build the crane functionality based on the composed modules
          crane = craneLattice.perSystem {
            inherit pkgs lib system args rust dbg gitRev;
            inputs = {
              inherit inputs; # Pass all original inputs
              self = inputs.self; # Ensure self is passed correctly
            };
          };
        in
        {
          # Expose the crane functionality
          inherit (crane)
            cargoWorkspaceSrc
            buildWorkspaceMember
            buildWasmContract
            allCargoTomls
            craneLib
            workspaceCargoVendorDir
            cargoWorkspaceAttrs
            cargoArtifacts
            checks
            packages
            ;
          # Also expose the architectural definition for introspection
          inherit primeLayers layerVibes;
        };

    in
    {
      # Expose the mkArchitecturalCrane function
      inherit mkArchitecturalCrane;

      # Optionally, instantiate it directly if this file is meant to be the primary entry point
      # architecturalCrane = mkArchitecturalCrane {
      #   root = ../../.; # Assuming this is the correct root
      #   inherit (args) gitRev;
      #   inherit inputs pkgs lib system args rust dbg;
      # };
    };
}
