local M = {}

local defaults = {
    -- Command to start the server. Wrap in a shell if you need env vars, e.g.:
    --   cmd = { "sh", "-c", "RUST_BACKTRACE=1 swls" }
    cmd = { "swls" },
    filetypes = { "turtle", "sparql", "jsonld" },
    -- Root directory for the LSP. Defaults to cwd.
    root_dir = nil,
    init_options = {
        sparql = false,
    },
    settings = {},
    inlay_hints = true,
}

function M.setup(opts)
    opts = vim.tbl_deep_extend("force", defaults, opts or {})

    vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("swls", { clear = true }),
        pattern = opts.filetypes,
        callback = function(args)
            local bufnr = args.buf

            if opts.inlay_hints and vim.lsp.inlay_hint then
                vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
            end

            vim.lsp.start({
                name = "swls",
                cmd = opts.cmd,
                root_dir = opts.root_dir or vim.fn.getcwd(),
                init_options = opts.init_options,
                settings = opts.settings,
            })
        end,
    })
end

return M
