# nix-wasm-zig

Zig library for writing [Determinate Nix](https://github.com/DeterminateSystems/nix-src) WASM builtins.

See `src/builtins/minimal.zig` for a minimal template.

Each builtin module is invoked via the `builtins.wasm` Nix primitive (requires wasm-builtins experimental feature):

```nix
# freestanding builtins (non-wasi mode)
builtins.wasm { path = ./zig-out/bin/non-wasi-minimal.wasm; function = "example"; } "Hello, World!"
# => "Hello, World!"

# wasip1 builtins (wasi mode)
builtins.wasm { path = ./zig-out/bin/wasi-minimal.wasm; } null # or any argument, returns null anyway...
# warning: 'wasi-minimal.wasm': Hello, world!
# => null
```

## Requirements

- Zig 0.15.2
- [Determinate Nix](https://github.com/DeterminateSystems/nix-src) (with WASM builtin support)

```sh
nix develop # development
nix build # outputs wasm files under result/bin
```