{
  description = "Description for the project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    devenv = {
      url = "github:cachix/devenv";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    crane = {
      url = "github:ipetkov/crane";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ flake-parts, nix2container, crane, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.devenv.flakeModule
      ];
      systems = [ "x86_64-linux" "x86_64-darwin" ];

      perSystem = { config, self', inputs', pkgs, system, ... }:
        let
          inherit (pkgs) lib;

          name = "nix-rs-prac-parts";

          craneLib = crane.lib.${system};
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
          packages.container = pkgs.dockerTools.buildLayeredImage {
            name = name;
            tag = "latest";
            created = "now";
            contents = [ config.packages.default ];
            config = {
              EntryPoint = [ "${config.packages.default}/bin/nix-rs-prac-parts" ];
            };
          };

          apps.skopeo = {
            type = "app";
            program = "${pkgs.skopeo}/bin/skopeo";
          };

          devenv.shells.default = {
            name = "nix-rs-prac-parts";

            # https://devenv.sh/reference/options/
            packages = with pkgs; [
              git
              hello
            ];

            scripts.build-container.exec = ''
              nix build '.#container'
            '';

            scripts.copy-container.exec = with config; ''
              ${apps.skopeo.program} --insecure-policy copy docker-archive:${packages.container} containers-storage:localhost/${name}:latest
              ${apps.skopeo.program} --insecure-policy inspect containers-storage:localhost/${name}:latest
            '';

            enterShell = ''
            '';

            languages.rust.enable = true;
          };

        };
      flake = {
        # The usual flake attributes can be defined here, including system-
        # agnostic ones like nixosModule and system-enumerating ones, although
        # those are more easily expressed in perSystem.

      };
    };
}
