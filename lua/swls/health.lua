local M = {}

function M.check()
    vim.health.start("swls")

    local swls = require("swls")
    local bin = swls._managed_path()

    if vim.fn.filereadable(bin) == 1 then
        vim.health.ok("managed binary: " .. bin)
        local version = vim.trim(vim.fn.system({ bin, "--version" }))
        if version ~= "" then vim.health.info(version) end
    else
        vim.health.info("no managed binary at " .. bin .. " (will be offered on next start)")
    end

    local path_bin = vim.fn.exepath("swls")
    if path_bin ~= "" and path_bin ~= bin then
        vim.health.ok("swls in PATH: " .. path_bin)
        local version = vim.trim(vim.fn.system({ "swls", "--version" }))
        if version ~= "" then vim.health.info(version) end
    end

    if vim.fn.filereadable(bin) == 0 and path_bin == "" then
        vim.health.warn("swls not found", {
            "A download will be offered automatically on the next startup",
            "Or install manually: cargo install swls",
        })
    end

    if vim.fn.executable("curl") == 1 then
        vim.health.ok("curl available (required for downloads)")
    else
        vim.health.warn("curl not found — automatic downloads will not work")
    end

    if vim.lsp.inlay_hint then
        vim.health.ok("inlay hints supported (Neovim " .. tostring(vim.version()) .. ")")
    else
        vim.health.warn("inlay hints not available — upgrade to Neovim 0.10+")
    end
end

return M
