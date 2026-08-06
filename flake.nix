{
  description = "Performance-Aware Programming course dev env";

  inputs = {
    # Unstable for a current toolchain: LLVM 20-era clang and clangd. Nothing
    # here has a version-sensitive dependency chain that would justify pinning
    # to a stable release, so we track the latest. `nix flake update` bumps it.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      # `nix develop` — a hacking environment. Everything below lands on
      # PATH the moment you enter the shell; `.envrc` (`use flake`) makes direnv
      # do that automatically whenever you're in the tree.
      #
      # No `clang-tools` package needed: the clang that clangStdenv pulls in
      # already ships clangd, clang-format and clang-tidy, so adding it would
      # just put a second, separately-versioned copy of each ahead on PATH.
      devShells = forAllSystems (
        pkgs:
        let
          # nixpkgs builds Odin against LLVM 18, whose compiler-rt no longer
          # compiles against the libcxx 21 / SDK 26 headers that unstable now
          # ships — `std::__countl_zero` changed constraints out from under the
          # fuzzer runtime, so the dependency fails to build from source.
          #
          # Retargeting to LLVM 21 sidesteps it and is strictly cheaper: the
          # shell's clangStdenv is already LLVM 21, so this shares one toolchain
          # instead of pulling a second one in, and every dependency comes from
          # the binary cache. Drop this override once nixpkgs bumps Odin itself.
          odin = pkgs.odin.override { llvmPackages_18 = pkgs.llvmPackages_21; };
          ols = pkgs.ols.override { inherit odin; };
        in
        {
          # The compiler comes from the shell's stdenv, not from `packages`.
          # Overriding it to clangStdenv is what actually swaps `cc`/`c++` and
          # the wrapper's include paths; listing `clang` in `packages` instead
          # would leave the default stdenv's compiler on PATH as well and the
          # two would disagree about where the standard library lives.
          # On Darwin this is already the default, so the override is a no-op
          # there — it exists to give Linux the same compiler as macOS.
          default = (pkgs.mkShell.override { stdenv = pkgs.clangStdenv; }) {
            packages = [
              # nasm assembles the course's 8086 listings. It's a cross-assembler
              # here — on aarch64-darwin it still emits x86-16/64 machine code,
              # which is all we need: the workflow is assemble → decode →
              # re-assemble → diff the two binaries, never execute them natively.
              pkgs.nasm
              odin
              ols
            ];

            shellHook = ''
              echo "dev env — $(c++ --version | head -n1)"
            '';
          };
        }
      );
    };
}
