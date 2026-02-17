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

  outputs = { self, nixpkgs, ... }@inputs: {
    devShells."x86_64-linux".default = let
      inherit ((import "${inputs.infuse.outPath}/default.nix" { inherit (nixpkgs) lib; }).v1) infuse;
      pkgs = nixpkgs.legacyPackages."x86_64-linux";
    in pkgs.mkShell {
      packages = __attrValues {
        zig = inputs.zig.packages.x86_64-linux."0.15.2";
        inherit (pkgs) zls wabt;
        inherit (inputs.nix.packages.x86_64-linux) nix-cli;

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
        });
      };
    };
  };
}
