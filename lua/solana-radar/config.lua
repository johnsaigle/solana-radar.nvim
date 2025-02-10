local M = {}

local defaults = {
    enabled = true,
    severity_map = {
        error = vim.diagnostic.severity.ERROR,
        warning = vim.diagnostic.severity.WARN,
        note = vim.diagnostic.severity.INFO,
    },
    default_severity = vim.diagnostic.severity.WARN,
    extra_args = {},
    filetypes = {"rust"},
    keymaps = {
        set_severity = "<leader>rs",
    },
}

function M.print_config()
    local config_lines = { "Current Radar Configuration:" }
    for k, v in pairs(M.config) do
        if type(v) == "table" then
            table.insert(config_lines, string.format("%s: %s", k, vim.inspect(v)))
        else
            table.insert(config_lines, string.format("%s: %s", k, tostring(v)))
        end
    end
    vim.notify(table.concat(config_lines, "\n"), vim.log.levels.INFO)
end

function M.toggle()
    if not namespace then
        namespace = vim.api.nvim_create_namespace("radar-nvim")
    end
    M.config.enabled = not M.config.enabled
    if not M.config.enabled then
        local bufs = vim.api.nvim_list_bufs()
        for _, buf in ipairs(bufs) do
            if vim.api.nvim_buf_is_valid(buf) then
                vim.diagnostic.reset(namespace, buf)
            end
        end
        vim.notify("Radar diagnostics disabled", vim.log.levels.INFO)
    else
        vim.notify("Radar diagnostics enabled", vim.log.levels.INFO)
        require('radar-diagnostics').scan()
    end
end

function M.setup_keymaps()
    if M.config.keymaps.set_severity then
        vim.keymap.set('n', M.config.keymaps.set_severity, function()
            vim.ui.select(
                { "ERROR", "WARN", "INFO" },
                {
                    prompt = "Select minimum severity level:",
                    format_item = function(item)
                        return string.format("%s (%d)", item, vim.diagnostic.severity[item])
                    end,
                },
                function(choice)
                    if choice then
                        local severity = vim.diagnostic.severity[choice]
                        M.set_minimum_severity(severity)
                    end
                end
            )
        end, { desc = "Set [r]adar minimum [s]everity" })
    end
end

function M.set_minimum_severity(level)
    if not vim.tbl_contains(vim.tbl_values(vim.diagnostic.severity), level) then
        vim.notify("Invalid severity level", vim.log.levels.ERROR)
        return
    end
    M.config.default_severity = level
    vim.notify(string.format("Minimum severity set to: %s", level), vim.log.levels.INFO)
end

function M.setup(opts)
    M.config = vim.tbl_deep_extend("force", {}, defaults, opts or {})
end

M.config = vim.deepcopy(defaults)
return M
