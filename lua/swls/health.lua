local M = {}

function M.check()
    vim.health.start("swls")

    local path = vim.fn.exepath("swls")
    if path ~= "" then
        vim.health.ok("swls found: " .. path)
        local version = vim.trim(vim.fn.system({ "swls", "--version" }))
        if version ~= "" then
            vim.health.info(version)
        end
    else
        vim.health.warn("swls not found in PATH", {
            "Install with: cargo install swls",
            "Or download a binary from the GitHub releases page",
        })
    end

    if vim.lsp.inlay_hint then
        vim.health.ok("inlay hints supported (Neovim " .. tostring(vim.version()) .. ")")
    else
        vim.health.warn("inlay hints not available — upgrade to Neovim 0.10+")
    end
end

return M
