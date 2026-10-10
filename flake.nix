{
  # Build environment for the macOS and iOS ports:
  #
  #   nix develop
  #
  # It deliberately has no nix C compiler, so Xcode's clang and SDKs are used.
  # nix's compiler wrapper can't target iOS. Xcode must be installed.
  #
  # macOS: the libraries come from nixpkgs (SDL3, OpenAL Soft, libpng, FFmpeg).
  #   macos/build-app.sh
  #
  # iOS: the libraries are built from source into build/ios-deps, so only the
  # build tools are needed.
  #   ios/build-ipa.sh
  description = "Build environment for the Simpsons: Hit & Run macOS and iOS ports";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "aarch64-darwin" "x86_64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      devShells = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system}; in
        {
          default = pkgs.mkShellNoCC {
            nativeBuildInputs = with pkgs; [
              cmake
              ninja
              pkg-config
            ];

            # Only used by the macOS build
            buildInputs = with pkgs; [
              sdl3
              libpng
              openal-soft
              ffmpeg_6
            ];
          };
        });
    };
}
