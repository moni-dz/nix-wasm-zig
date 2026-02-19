# nix-wasm-zig

Zig library for writing [Determinate Nix](https://github.com/DeterminateSystems/nix-src) WASM builtins.

See `src/builtins/minimal.zig` for a minimal template.

Each builtin module is invoked via the `builtins.wasm` Nix primitive (requires wasm-builtins experimental feature):

```nix
builtins.wasm ./zig-out/bin/minimal.wasm "example" "Hello, World!"
# => "Hello, World!"
```

## Requirements

- Zig 0.15.2
- [Determinate Nix](https://github.com/DeterminateSystems/nix-src) (with WASM builtin support)

```sh
nix develop # development
nix build # outputs wasm file under result/bin
```