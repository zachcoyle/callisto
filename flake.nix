{
  description = "Καλλιστώ 😵‍💫";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    systems.url = "github:nix-systems/default";
    crane = {
      url = "github:ipetkov/crane";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.rust-analyzer-src.follows = "";
    };
    advisory-db = {
      url = "github:rustsec/advisory-db";
      flake = false;
    };
    devshell = {
      url = "github:numtide/devshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      flake-parts,
      crane,
      fenix,
      advisory-db,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ ];
      systems = import inputs.systems;
      perSystem =
        {
          config,
          self',
          inputs',
          pkgs,
          system,
          ...
        }:
        let
          craneLib = crane.mkLib pkgs;

          src = craneLib.cleanCargoSource ./.;

          commonArgs = {
            inherit src;
            strictDeps = true;

            buildInputs = [ ] ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [ ];

            # Additional environment variables can be set directly
            # MY_CUSTOM_VAR = "some value";
          };

          craneLibLLvmTools = craneLib.overrideToolchain (
            fenix.packages.${system}.complete.withComponents [
              "cargo"
              "llvm-tools"
              "rustc"
            ]
          );

          cargoArtifacts = craneLib.buildDepsOnly commonArgs;

          callisto = craneLib.buildPackage (commonArgs // { inherit cargoArtifacts; });
        in
        {
          packages =
            {
              default = callisto;
            }
            // pkgs.lib.optionalAttrs (!pkgs.stdenv.isDarwin) {
              my-crate-llvm-coverage = craneLibLLvmTools.cargoLlvmCov (commonArgs // { inherit cargoArtifacts; });
            };

          devShells.default = craneLib.devShell {
            # Inherit inputs from checks.
            checks = self.checks.${system};

            # Additional dev-shell environment variables can be set directly
            # MY_CUSTOM_DEVELOPMENT_VAR = "something else";

            packages = with pkgs; [ just ];
          };

          formatter = pkgs.nixfmt-rfc-style;

          checks = {

            # Build the crate as part of `nix flake check` for convenience
            inherit callisto;
            # Run clippy (and deny all warnings) on the crate source,
            # again, reusing the dependency artifacts from above.
            #
            # Note that this is done as a separate derivation so that
            # we can block the CI if there are issues here, but not
            # prevent downstream consumers from building our crate by itself.
            callisto-clippy = craneLib.cargoClippy (
              commonArgs
              // {
                inherit cargoArtifacts;
                cargoClippyExtraArgs = "--all-targets -- --deny warnings";
              }
            );

            callisto-doc = craneLib.cargoDoc (commonArgs // { inherit cargoArtifacts; });

            callisto-fmt = craneLib.cargoFmt { inherit src; };

            callisto-audit = craneLib.cargoAudit { inherit src advisory-db; };

            # Audit licenses
            callisto-deny = craneLib.cargoDeny { inherit src; };

            # Run tests with cargo-nextest
            # Consider setting `doCheck = false` on `callisto` if you do not want
            # the tests to run twice
            callisto-nextest = craneLib.cargoNextest (
              commonArgs
              // {
                inherit cargoArtifacts;
                partitions = 1;
                partitionType = "count";
              }
            );
          };
        };
    };
}
