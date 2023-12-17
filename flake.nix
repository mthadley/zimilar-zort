{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/release-23.11";

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let pkgs = nixpkgs.legacyPackages.${system};
      in
      rec {
        devShells.default = pkgs.mkShell
          {
            nativeBuildInputs = with pkgs; [
              hyperfine
              zig
              zls
            ];
          };

        # Largely stolen from gyro:
        # https://github.com/mattnite/gyro/blob/19cf64d93a5ad917a9e49f2b58f006a10210cb84/flake.nix#L37-L62
        packages.default = pkgs.stdenv.mkDerivation {
          name = "zimilar-zort";
          src = ./.;

          nativeBuildInputs = with pkgs; [
            zig
          ];

          preBuild = ''
            export HOME=$TMPDIR
          '';

          installPhase = ''
            runHook preInstall
            zig build -Doptimize=ReleaseFast --prefix $out install
            runHook postInstall
          '';

          installFlags = [ "DESTDIR=$(out)" ];

          meta = {
            description = "Sort files from STDIN based on a similar word.";
            platforms = with pkgs.lib.platforms; linux ++ darwin;
            maintainers = [{
              email = "m@mthadley.com";
              github = "mthadley";
              name = "Michael Hadley";
            }];
          };
        };

        overlays.default = final: prev: {
          zimilar-zort = packages.default;
        };
      }
    );
}
