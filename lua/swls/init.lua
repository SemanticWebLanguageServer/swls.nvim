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

-- `swls --version` may report a bare semver ("0.3.0") while stable release
-- tags are prefixed ("swls-v0.3.0"); compare them without the prefix.
local function normalize_version(v)
    return (v:gsub("^swls%-v", ""))
end

local function github_api(path, cb)
    local url = "https://api.github.com/repos/" .. REPO .. path
    local done = false
    local function finish(value, err)
        if done then return end
        done = true
        cb(value, err)
    end
    vim.fn.jobstart({ "curl", "-sfL", "--max-time", "10", url }, {
        stdout_buffered = true,
        on_stdout = function(_, data)
            local body = table.concat(data, "\n")
            if body:match("^%s*$") then return end
            local ok, value = pcall(vim.json.decode, body)
            if ok and type(value) == "table" then
                finish(value, nil)
            else
                finish(nil, "invalid response from " .. url)
            end
        end,
        on_exit = function(_, code)
            finish(nil, "curl exited " .. code .. " for " .. url)
        end,
    })
end

-- Calls `cb(release, err)` with `release = { tag = ..., version = ... }`:
-- `tag` is what the assets are downloaded from, `version` what the binary
-- from that release reports.
local function get_latest_release(channel, cb)
    if channel == "nightly" then
        -- A single rolling release, rebuilt on every push to main. Its name is
        -- `nightly-<short sha>`, which is also what the binary reports.
        github_api("/releases/tags/nightly", function(release, err)
            if err then return cb(nil, err) end
            if type(release.name) ~= "string" then
                return cb(nil, "nightly release has no name")
            end
            cb({ tag = "nightly", version = release.name }, nil)
        end)
        return
    end

    github_api("/releases", function(releases, err)
        if err then return cb(nil, err) end
        -- Only main binary releases (swls-vX.Y.Z), not sub-crate tags
        -- (swls-lang-*, swls-core-*), and no pre-releases.
        for _, r in ipairs(releases) do
            if type(r.tag_name) == "string" and r.tag_name:match("^swls%-v%d")
                and r.prerelease ~= true and r.draft ~= true then
                return cb({ tag = r.tag_name, version = normalize_version(r.tag_name) }, nil)
            end
        end
        cb(nil, "no stable release found")
    end)
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

local function check_for_updates(channel, verbose)
    local bin = managed_path()
    local current = vim.fn.filereadable(bin) == 1 and normalize_version(version_of(bin)) or ""

    get_latest_release(channel, function(release, err)
        if err then
            if verbose then
                vim.schedule(function()
                    vim.notify("swls: update check failed: " .. err, vim.log.levels.WARN)
                end)
            end
            return
        end
        local latest = release.version
        if current == latest then
            if verbose then
                vim.schedule(function()
                    vim.notify("swls: already at latest " .. channel .. " version (" .. current .. ")",
                        vim.log.levels.INFO)
                end)
            end
            return
        end

        local is_fresh = current == ""
        local prompt = is_fresh
            and "swls: language server available. Install it?"
            or ("swls: update available (" .. current .. " → " .. latest .. ")")

        vim.schedule(function()
            vim.ui.select({ "Yes", "No" }, { prompt = prompt }, function(choice)
                if choice ~= "Yes" then return end
                download_release(release.tag, function(_, dl_err)
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
    init_options = { },
    settings = {},
    inlay_hints = true,
    -- Check GitHub for a newer release on every startup.
    check_update = true,
    -- Which releases to install and update to:
    --   "stable"  tagged releases (swls-vX.Y.Z)
    --   "nightly" rolling build of main, rebuilt on every push
    channel = "stable",
}

function M.setup(opts)
    opts = vim.tbl_deep_extend("force", defaults, opts or {})
    if opts.channel ~= "stable" and opts.channel ~= "nightly" then
        vim.notify("swls: unknown channel '" .. tostring(opts.channel) .. "', using 'stable'",
            vim.log.levels.WARN)
        opts.channel = "stable"
    end
    M._channel = opts.channel

    vim.api.nvim_create_user_command("SwlsUpdate", function()
        check_for_updates(opts.channel, true)
    end, { desc = "Check GitHub for a newer swls binary on the configured channel" })

    local function resolve_cmd()
        if opts.cmd then return opts.cmd end
        local bin = managed_path()
        if vim.fn.filereadable(bin) == 1 then return { bin } end
        if vim.fn.executable("swls") == 1 then return { "swls" } end
        return nil
    end

    if opts.check_update then
        vim.defer_fn(function() check_for_updates(opts.channel, false) end, 500)
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
