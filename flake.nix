{
  inputs = {
    zig.url = "github:mitchellh/zig-overlay";
    nixpkgs.url = "github:nixos/nixpkgs/master";
    nix.url = "github:DeterminateSystems/nix-src";

    infuse = {
      url = "git+https://codeberg.org/amjoseph/infuse.nix.git";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, ... }@inputs: let
    inherit ((import "${inputs.infuse.outPath}/default.nix" { inherit (nixpkgs) lib; }).v1) infuse;
    supportedSystems = [ "aarch64-darwin" "x86_64-linux" ];

    forAllSystems = f: inputs.nixpkgs.lib.genAttrs supportedSystems (system: f {
      pkgs = nixpkgs.legacyPackages.${system};
      inherit system;
      inherit (nixpkgs) lib;
    });

  in {

    packages = forAllSystems ({ pkgs, lib, ... }: rec {
      default = nix-wasm-zig-plugins;

      nix-wasm-zig-plugins = pkgs.stdenv.mkDerivation {
        pname = "nix-wasm-zig-plugins";
        version = "0.1.0";

        src = lib.fileset.toSource {
          root = ./.;
          fileset = lib.fileset.fileFilter (f: f.hasExt "zig" || f.hasExt "zon") ./.;
        };

        nativeBuildInputs = [
          pkgs.zig
          pkgs.binaryen
        ];

        dontSetZigDefaultFlags = true;

        zigBuildFlags = [ "-Doptimize=ReleaseFast" ];
      };
    });

    devShells = forAllSystems ({ pkgs, system, ... }: {
      default = pkgs.mkShell {
        packages = __attrValues {
          zig = inputs.zig.packages.${system}."0.15.2";
          inherit (pkgs) zls wabt binaryen;
          inherit (inputs.nix.packages.${system}) nix-cli;


          zigdoc = pkgs.stdenv.mkDerivation (final: {
            pname = "zigdoc";
            version = "0.2.2";

            src = pkgs.fetchFromGitHub {
              owner = "rockorager";
              repo = "zigdoc";
              tag = "v${final.version}";
              hash = "sha256-bvZnNiJ6YbsoQb41oAWzZNErCcAtKKudQMwvAfa4UEA=";
            };

            nativeBuildInputs = [ pkgs.zig ];

            postPatch = ''
              substituteInPlace build.zig \
                --replace-fail '"../README.md"' '"README.md"'
            '';
          });
        };
      };
    });
  };
}
