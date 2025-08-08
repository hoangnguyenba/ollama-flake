{
  description = "Ollama - Run large language models locally";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;  # Allow CUDA and other unfree packages
          };
        };
      in
      {
        packages.default = pkgs.stdenv.mkDerivation rec {
          pname = "ollama";
          version = "0.11.4";

          src = pkgs.fetchurl {
            url = "https://github.com/ollama/ollama/releases/download/v${version}/ollama-linux-amd64.tgz";
            sha256 = "0czf1dw64zr8xq8s1jdvarzddqg90030v3z81lyimrplrjraz253";
          };

          nativeBuildInputs = with pkgs; [
            autoPatchelfHook
            makeWrapper
          ];

          # Tell autoPatchelfHook to ignore missing GPU libraries
          autoPatchelfIgnoreMissingDeps = [
            "libhipblas.so.2"
            "librocblas.so.4"
            "libamdhip64.so.6"
            # "libcuda.so.1"
          ];

          buildInputs = with pkgs; [
            stdenv.cc.cc.lib
            glibc
            zlib
            # CUDA libraries (if you have CUDA support)
            cudaPackages.cuda_cudart
            cudaPackages.libcublas
            # cudaPackages.cuda_driver
          ];

          sourceRoot = ".";

          installPhase = ''
            runHook preInstall
            
            mkdir -p $out/bin $out/lib/ollama
            
            # Install the main binary
            cp bin/ollama $out/bin/
            chmod +x $out/bin/ollama
            
            # Install all the shared libraries
            cp -r lib/ollama/* $out/lib/ollama/
            
            # Make sure the binary can find the libraries
            wrapProgram $out/bin/ollama \
              --set LD_LIBRARY_PATH "$out/lib/ollama:${pkgs.lib.makeLibraryPath buildInputs}"
            
            runHook postInstall
          '';

          meta = with pkgs.lib; {
            description = "Get up and running with large language models locally";
            homepage = "https://ollama.ai";
            license = licenses.mit;
            platforms = [ "x86_64-linux" ];
            maintainers = [ ];
          };
        };

        # Create an app for easy running
        apps.default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/ollama";
        };

        # Development shell
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            self.packages.${system}.default
          ];
        };

        nixosModules.default = { config, lib, pkgs, ... }:
          {
            nixpkgs.overlays = [
              (final: prev: {
                ollama = self.packages.${system}.default;
              })
            ];

            options.services.ollama = {
              enable = lib.mkEnableOption "Enable the Ollama service";
            };

            config = lib.mkIf config.services.ollama.enable {
              users.users.ollama = {
                isSystemUser = true;
                group = "ollama";
                home = "/var/lib/ollama";
                createHome = true;
              };
              users.groups.ollama = {};

              systemd.services.ollama = {
                description = "Ollama service";
                after = [ "network-online.target" ];
                wantedBy = [ "multi-user.target" ];
                serviceConfig = {
                  ExecStart = "${pkgs.ollama}/bin/ollama serve";
                  Restart = "always";
                  RestartSec = "3s";
                  User = "ollama";
                  Group = "ollama";
                };
              };
            };
          };
      }
    );
}