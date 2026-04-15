{
  description = "Neovide package and development shell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      flake-utils,
      rust-overlay,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ (import rust-overlay) ];
        };

        lib = pkgs.lib;
        cargoToml = builtins.fromTOML (builtins.readFile ./Cargo.toml);

        rustToolchain = pkgs.rust-bin.stable.latest.default.override {
          extensions = [
            "clippy"
            "rust-src"
            "rustfmt"
          ];
        };

        rustPlatform = pkgs.makeRustPlatform {
          cargo = rustToolchain;
          rustc = rustToolchain;
        };

        linuxLibs = with pkgs; [
          alsa-lib
          expat
          fontconfig
          freetype
          libGL
          libxkbcommon
          wayland
          xorg.libX11
          xorg.libXcomposite
          xorg.libXcursor
          xorg.libXext
          xorg.libXfixes
          xorg.libXi
          xorg.libXrandr
          xorg.libXrender
          xorg.libxcb
        ];

        skiaExternals = {
          expat = {
            url = "https://chromium.googlesource.com/external/github.com/libexpat/libexpat.git";
            rev = "8e49998f003d693213b538ef765814c7d21abada";
            sha256 = "sha256-zP2kiB4nyLi0/I8OsRhxKG0qRGPe2ALLQ+HHfqlBJ6Y=";
          };
          libjpeg-turbo = {
            url = "https://chromium.googlesource.com/chromium/deps/libjpeg_turbo.git";
            rev = "e14cbfaa85529d47f9f55b0f104a579c1061f9ad";
            sha256 = "sha256-Ig+tmprZDvlf/M72/DTar2pbxat9ZElgSqdXdoM0lPs=";
          };
          icu = {
            url = "https://chromium.googlesource.com/chromium/deps/icu.git";
            rev = "364118a1d9da24bb5b770ac3d762ac144d6da5a4";
            sha256 = "sha256-frsmwYMiFixEULsE91x5+p98DvkyC0s0fNupqjoRnvg=";
          };
          zlib = {
            url = "https://chromium.googlesource.com/chromium/src/third_party/zlib";
            rev = "646b7f569718921d7d4b5b8e22572ff6c76f2596";
            sha256 = "sha256-jNj6SuTZ5/a7crtYhxW3Q/TlfRMNMfYIVxDlr7bYdzQ=";
          };
          harfbuzz = {
            url = "https://chromium.googlesource.com/external/github.com/harfbuzz/harfbuzz.git";
            rev = "31695252eb6ed25096893aec7f848889dad874bc";
            sha256 = "sha256-Csyz08JTNXfY2fo27x1Eg1CqO/tt8Rt9udr3KflojSg=";
          };
          wuffs = {
            url = "https://skia.googlesource.com/external/github.com/google/wuffs-mirror-release-c.git";
            rev = "e3f919ccfe3ef542cfc983a82146070258fb57f8";
            sha256 = "sha256-373d2F/STcgCHEq+PO+SCHrKVOo6uO1rqqwRN5eeBCw=";
          };
          libpng = {
            url = "https://skia.googlesource.com/third_party/libpng.git";
            rev = "4e3f57d50f552841550a36eabbb3fbcecacb7750";
            sha256 = "sha256-tNRrA9RUp6Mi7dbIB/70a/4tn/JxAsTUb9EI9nlXLjM=";
          };
        };

        skiaSource =
          let
            repo = pkgs.fetchFromGitHub {
              owner = "rust-skia";
              repo = "skia";
              tag = "m145-0.92.0";
              hash = "sha256-9N780AwheKBJRcZC4l/uWFNq+oOyoNp4M6dJAVVAFeo=";
            };

            externals = pkgs.linkFarm "skia-externals" (
              lib.mapAttrsToList (name: value: {
                inherit name;
                path = pkgs.fetchgit value;
              }) skiaExternals
            );
          in
          pkgs.runCommand "skia-source" { } ''
            cp -R ${repo} $out
            chmod -R +w $out
            ln -s ${externals} $out/third_party/externals
          '';

        package = rustPlatform.buildRustPackage.override { stdenv = pkgs.clangStdenv; } {
          pname = cargoToml.package.name;
          version = cargoToml.package.version;
          src = ./.;

          cargoLock = {
            lockFile = ./Cargo.lock;
          };

          env = {
            SKIA_SOURCE_DIR = skiaSource;
            SKIA_GN_COMMAND = "${pkgs.gn}/bin/gn";
            SKIA_NINJA_COMMAND = "${pkgs.ninja}/bin/ninja";
          };

          nativeBuildInputs = [
            pkgs.makeWrapper
            pkgs.pkg-config
            pkgs.python3
            pkgs.removeReferencesTo
          ]
          ++ lib.optionals pkgs.stdenv.isDarwin [ pkgs.cctools.libtool ];

          nativeCheckInputs = [ pkgs.neovim ];

          buildInputs = [
            pkgs.SDL2
            pkgs.fontconfig
            rustPlatform.bindgenHook
          ];

          postFixup = ''
            # skia embeds the absolute source path into the resulting binary.
            remove-references-to -t "$SKIA_SOURCE_DIR" $out/bin/neovide
          ''
          + lib.optionalString pkgs.stdenv.isLinux ''
            wrapProgram $out/bin/neovide \
              --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath linuxLibs}
          '';

          postInstall =
            lib.optionalString pkgs.stdenv.isDarwin ''
              mkdir -p $out/Applications
              cp -r extra/osx/Neovide.app $out/Applications
              ln -s $out/bin $out/Applications/Neovide.app/Contents/MacOS
            ''
            + lib.optionalString pkgs.stdenv.isLinux ''
              for n in 16x16 32x32 48x48 256x256; do
                install -m444 -D "assets/neovide-$n.png" \
                  "$out/share/icons/hicolor/$n/apps/neovide.png"
              done
              install -m444 -Dt $out/share/icons/hicolor/scalable/apps assets/neovide.svg
              install -m444 -Dt $out/share/applications assets/neovide.desktop
            '';

          disallowedReferences = [ skiaSource ];

          meta = {
            description = cargoToml.package.description;
            homepage = cargoToml.package.homepage;
            license = lib.licenses.mit;
            mainProgram = cargoToml.package.name;
            platforms = lib.platforms.unix;
          };
        };
      in
      {
        packages.default = package;
        packages.neovide = package;

        apps.default = flake-utils.lib.mkApp {
          drv = package;
        };

        devShells.default = pkgs.mkShell {
          inputsFrom = [ package ];

          packages = [
            rustToolchain
            pkgs.cmake
            pkgs.git
            pkgs.ninja
            pkgs.openssl
            pkgs.pkg-config
            pkgs.python3
          ]
          ++ lib.optionals pkgs.stdenv.isLinux linuxLibs;
        };
      }
    );
}
