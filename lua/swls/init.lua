local M = {}

local REPO = "SemanticWebLanguageServer/swls"
local PLAIN = "swls"
local VERSION_PATTERN = "version=(%S+)"

local function binary_name()
    return vim.fn.has("win32") == 1 and "swls.exe" or "swls"
end

local function get_target()
    local uname = vim.loop.os_uname()
    local sys = uname.sysname
    local arch = uname.machine

    if vim.fn.has("win32") == 1 then
        return arch:find("64") and "windows-x86_64.exe" or "windows-arm64.exe"
    elseif sys == "Linux" then
        if arch == "x86_64" then return "linux-x86_64" end
        if arch:find("aarch64") then return "linux-aarch64" end
    elseif sys == "Darwin" then
        if arch == "arm64" or arch:find("aarch64") then return "macos-arm64" end
        return "macos-x86_64"
    end
    return nil
end

local function install_dir()
    return vim.fn.stdpath("data") .. "/swls"
end

local function managed_path()
    return install_dir() .. "/" .. binary_name()
end

M._managed_path = managed_path

local function version_of(cmd)
    local out = vim.fn.system({ cmd, "--version" })
    return out:match(VERSION_PATTERN) or ""
end

local function get_latest_release(cb)
    local url = "https://api.github.com/repos/" .. REPO .. "/releases"
    local done = false
    vim.fn.jobstart({ "curl", "-sfL", "--max-time", "10", url }, {
        stdout_buffered = true,
        on_stdout = function(_, data)
            local body = table.concat(data, "\n")
            if body:match("^%s*$") then return end
            local ok, releases = pcall(vim.json.decode, body)
            if not ok or type(releases) ~= "table" then return end
            for _, r in ipairs(releases) do
                if r.tag_name and r.tag_name:match("^swls%-") then
                    done = true
                    cb(r.tag_name, nil)
                    return
                end
            end
        end,
        on_exit = function(_, code)
            if not done then
                cb(nil, "curl exited " .. code)
            end
        end,
    })
end

local function download_release(version, cb)
    local target = get_target()
    if not target then
        cb(nil, "unsupported platform: " .. vim.loop.os_uname().sysname .. "/" .. vim.loop.os_uname().machine)
        return
    end

    vim.fn.mkdir(install_dir(), "p")
    local tmp = install_dir() .. "/swls-tmp-" .. os.time()
    local dst = managed_path()
    local url = ("https://github.com/%s/releases/download/%s/%s-%s"):format(REPO, version, PLAIN, target)

    vim.notify("swls: downloading " .. version .. " …", vim.log.levels.INFO)

    vim.fn.jobstart({ "curl", "-fL", "--max-time", "120", "-o", tmp, url }, {
        on_exit = function(_, code)
            if code ~= 0 then
                vim.fn.delete(tmp)
                vim.schedule(function() cb(nil, "curl exited " .. code) end)
                return
            end
            if vim.fn.has("win32") == 0 then
                vim.fn.system({ "chmod", "+x", tmp })
            end
            vim.fn.rename(tmp, dst)
            vim.schedule(function() cb(dst, nil) end)
        end,
    })
end

local function check_for_updates()
    local bin = managed_path()
    local current = vim.fn.filereadable(bin) == 1 and version_of(bin) or ""

    get_latest_release(function(latest, err)
        if err or current == latest then return end

        local is_fresh = current == ""
        local prompt = is_fresh
            and "swls: language server available. Install it?"
            or ("swls: update available (" .. current .. " → " .. latest .. ")")

        vim.schedule(function()
            vim.ui.select({ "Yes", "No" }, { prompt = prompt }, function(choice)
                if choice ~= "Yes" then return end
                download_release(latest, function(_, dl_err)
                    if dl_err then
                        vim.notify("swls: install failed: " .. dl_err, vim.log.levels.ERROR)
                        return
                    end
                    local msg = is_fresh
                        and "swls: installed " .. latest .. ". Open a supported file to start the server."
                        or ("swls: updated to " .. latest .. ". Restart Neovim to apply.")
                    vim.notify(msg, vim.log.levels.INFO)
                end)
            end)
        end)
    end)
end

local defaults = {
    -- Override the server command. When nil the plugin uses the managed binary,
    -- then falls back to whatever `swls` is on PATH.
    cmd = nil,
    filetypes = { "turtle", "trig", "sparql", "jsonld" },
    root_dir = nil,
    init_options = { sparql = false },
    settings = {},
    inlay_hints = true,
    -- Check GitHub for a newer release on every startup.
    check_update = true,
}

function M.setup(opts)
    opts = vim.tbl_deep_extend("force", defaults, opts or {})

    local function resolve_cmd()
        if opts.cmd then return opts.cmd end
        local bin = managed_path()
        if vim.fn.filereadable(bin) == 1 then return { bin } end
        if vim.fn.executable("swls") == 1 then return { "swls" } end
        return nil
    end

    if opts.check_update then
        vim.defer_fn(check_for_updates, 500)
    end

    vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("swls", { clear = true }),
        pattern = opts.filetypes,
        callback = function(args)
            local cmd = resolve_cmd()
            if not cmd then
                vim.notify("swls: no binary found; will prompt to install shortly.", vim.log.levels.WARN)
                return
            end

            local bufnr = args.buf
            if opts.inlay_hints and vim.lsp.inlay_hint then
                vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
            end

            vim.lsp.start({
                name = "swls",
                cmd = cmd,
                root_dir = opts.root_dir or vim.fn.getcwd(),
                init_options = opts.init_options,
                settings = opts.settings,
            })
        end,
    })
end

return M
