# swls.nvim

Neovim plugin for the [Semantic Web Language Server](https://github.com/SemanticWebLanguageServer/swls).

Provides filetype detection for Turtle, SPARQL, and JSON-LD files and starts the LSP automatically.

## Features

- Filetype detection for `.ttl`, `.sq`, `.rq`, `.sparql`, `.jsonld`
- Auto-starts `swls` on matching buffers
- Inlay hints enabled by default
- `:checkhealth swls` to verify your setup

## Requirements

- Neovim 0.10+
- `swls` binary on your `PATH`

Install the binary via Cargo:

```sh
cargo install --git https://github.com/SemanticWebLanguageServer/swls.git swls
```

Or download a pre-built binary from the [releases page](https://github.com/SemanticWebLanguageServer/swls/releases).

## Installation

**lazy.nvim**

```lua
{
    "SemanticWebLanguageServer/swls.nvim",
    opts = {},
}
```

**packer.nvim**

```lua
use {
    "SemanticWebLanguageServer/swls.nvim",
    config = function()
        require("swls").setup()
    end,
}
```

**Manual** — clone into your packpath:

```sh
git clone https://github.com/SemanticWebLanguageServer/swls.nvim \
    ~/.local/share/nvim/site/pack/plugins/start/swls.nvim
```

Then call `require("swls").setup()` in your config.

## Configuration

`setup()` accepts an optional table. All fields are optional — unset fields keep their defaults.

```lua
require("swls").setup({
    -- Command used to start the server.
    cmd = { "swls" },

    -- Filetypes that trigger the LSP.
    filetypes = { "turtle", "sparql", "jsonld" },

    -- Root directory passed to the LSP. Defaults to cwd.
    root_dir = nil,

    -- Sent to the server at startup. Disable languages you don't use.
    init_options = {
        sparql = false,  -- SPARQL support is experimental
        -- turtle = false,
        -- jsonld = false,
    },

    -- Extra settings (sent via workspace/didChangeConfiguration).
    settings = {},

    -- Enable inlay hints on attach.
    inlay_hints = true,
})
```

### Examples

Run with `RUST_BACKTRACE` for debugging:

```lua
require("swls").setup({
    cmd = { "sh", "-c", "RUST_BACKTRACE=1 swls" },
})
```

Enable SPARQL support:

```lua
require("swls").setup({
    init_options = { sparql = true },
})
```

## Health check

```
:checkhealth swls
```

Reports whether the `swls` binary is found, its version, and whether your Neovim supports inlay hints.
