{
  description = "Description for the project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    devenv = {
      url = "github:cachix/devenv";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    crane = {
      url = "github:ipetkov/crane";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ flake-parts, fenix, crane, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.devenv.flakeModule
      ];
      systems = [ "x86_64-linux" "x86_64-darwin" ];

      perSystem = { config, self', inputs', lib, pkgs, system, ... }:
        let
          inherit (pkgs) lib;

          name = "nix-rs-prac-parts";

          fenixStable = fenix.packages.${system}.stable;

          rustToolchain = fenixStable.withComponents [
            "rustc"
            "cargo"
            "clippy"
            "rust-src"
            "rust-docs"
            "rust-analyzer"
            "llvm-tools-preview"
          ];
          craneLib = crane.lib.${system}.overrideToolchain (rustToolchain);
          src = craneLib.cleanCargoSource (craneLib.path ./.);

          # Common arguments can be set here to avoid repeating them later
          commonArgs = {
            inherit src;

            buildInputs = [
              # Add additional build inputs here
            ] ++ lib.optionals pkgs.stdenv.isDarwin [
              # Additional darwin specific inputs can be set here
              pkgs.libiconv
            ];

            # Additional environment variables can be set directly
            # MY_CUSTOM_VAR = "some value";
          };

          # Build *just* the cargo dependencies, so we can reuse
          # all of that work (e.g. via cachix) when running in CI
          cargoArtifacts = craneLib.buildDepsOnly commonArgs;

          # Build the actual crate itself, reusing the dependency
          # artifacts from above.
          my-crate = craneLib.buildPackage (commonArgs // {
            inherit cargoArtifacts;
          });
        in
        {
          # Per-system attributes can be defined here. The self' and inputs'
          # module parameters provide easy access to attributes of the same
          # system.

          # Equivalent to  inputs'.nixpkgs.legacyPackages.hello;
          packages.default = my-crate;
          packages.skopeo = pkgs.skopeo;

          packages.container = pkgs.dockerTools.buildLayeredImage {
            name = name;
            tag = "latest";
            created = "now";
            contents = [ config.packages.default ];
            config = {
              EntryPoint = [ "${config.packages.default}/bin/nix-rs-prac-parts" ];
            };
          };

          devenv.shells.default = {
            name = "nix-rs-prac-parts";

            # https://devenv.sh/reference/options/
            packages = with pkgs; [
              git
              hello
            ] ++ [ rustToolchain ];

            scripts.build-container.exec = ''
              nix build '.#container'
            '';

            scripts.copy-container.exec = with config; ''
              IMAGE_PATH=$(nix eval --raw '.#packages.${system}.container')
              ${lib.getExe packages.skopeo} --insecure-policy copy docker-archive:"$IMAGE_PATH" containers-storage:localhost/${name}:latest
              ${lib.getExe packages.skopeo} --insecure-policy inspect containers-storage:localhost/${name}:latest
            '';

            enterShell = ''
            '';
          };

        };
      flake = {
        # The usual flake attributes can be defined here, including system-
        # agnostic ones like nixosModule and system-enumerating ones, although
        # those are more easily expressed in perSystem.

      };
    };
}
