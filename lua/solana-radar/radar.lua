local M = {}

local namespace = nil
local config = require('solana-radar.config')

local function matches_filename(result, bufname)
    local result_path = result.locations[1].physicalLocation.artifactLocation.uri
    return bufname:match(vim.pesc(result_path) .. "$") ~= nil
end

local function is_valid_diagnostic(result, bufname)
    return result.locations
        and result.locations[1]
        and result.locations[1].physicalLocation
        and result.locations[1].physicalLocation.artifactLocation
        and result.locations[1].physicalLocation.artifactLocation.uri
        and matches_filename(result, bufname)
end

function M.scan()
    local null_ls_ok, null_ls = pcall(require, "null-ls")
    if not null_ls_ok then
        vim.notify("null-ls is required for radar-nvim", vim.log.levels.ERROR)
        return
    end

    local radar_generator = {
        method = null_ls.methods.DIAGNOSTICS,
        filetypes = { "rust" },
        generator = {
            runtime_condition = function()
                return config.enabled
            end,
            on_attach = function(client, bufnr)
                vim.api.nvim_buf_attach(bufnr, false, {
                    on_load = function()
                        if config.enabled then
                            null_ls.generator()({ bufnr = bufnr })
                        end
                    end
                })
            end,
            fn = function(params)
                -- Reset previous runs
                local namespace = vim.api.nvim_create_namespace("radar-nvim")
                vim.diagnostic.reset(namespace, params.bufnr)

                vim.notify("Running radar scan", vim.log.levels.INFO)

                -- Verify radar is installed.
                local cmd = vim.fn.exepath("radar")
                if cmd == "" then
                    vim.notify("radar executable not found in PATH", vim.log.levels.ERROR)
                    return {}
                end

                -- Store currently opened buffer so we can filter the Radar results for just this file.
                local filepath = vim.api.nvim_buf_get_name(params.bufnr)

                -- Build command arguments
                local temp_sarif = os.tmpname() .. ".sarif"
                local cwd = vim.fn.getcwd()
                local args = {
                    "-o", temp_sarif,
                    "-p", cwd,
                }

                -- Add any extra arguments
                for _, arg in ipairs(config.config.extra_args) do
                    table.insert(args, arg)
                end

                -- Run radar asynchronously
                vim.system(
                    vim.list_extend({ cmd }, args),
                    {
                        text = true,
                        cwd = cwd,
                    },
                    function(obj)
                        -- Open resulting SARIF file, parse, read results.
                        local fd = vim.uv.fs_open(temp_sarif, "r", 438)
                        local stat = vim.uv.fs_fstat(fd)
                        vim.uv.fs_read(fd, stat.size, 0, function(err, data)
                            vim.uv.fs_close(fd)
                            os.remove(temp_sarif)

                            if err or not data then
                                vim.notify("Failed to read SARIF file", vim.log.levels.ERROR)
                                return
                            end

                            local ok, parsed = pcall(vim.json.decode, data)
                            if not ok or not parsed then
                                vim.notify("Failed to parse radar output", vim.log.levels.ERROR)
                                return
                            end

                            local diags = {}
                            for _, run in ipairs(parsed.runs) do
                                local rules = {}
                                -- Build rule lookup table
                                for _, rule in ipairs(run.tool.driver.rules) do
                                    rules[rule.id] = rule
                                end

                                -- Convert results to diagnostics
                                local filtered_results = {}
                                for _, result in ipairs(run.results) do
                                    if is_valid_diagnostic(result, filepath) then
                                        filtered_results[result.ruleId] = result
                                    end
                                end

                                for rule_id, result in pairs(filtered_results) do
                                    local rule = rules[rule_id]
                                    if not rule then goto continue end

                                    local severity = config.config.severity_map[result.level] or
                                        config.config.default_severity

                                    local details = rule.fullDescription and rule.fullDescription.text or
                                        rule.shortDescription.text

                                    local message = rule.shortDescription.text

                                    local diag = {
                                        lnum = result.locations[1].physicalLocation.region.startLine - 1,
                                        col = result.locations[1].physicalLocation.region.startColumn - 1,
                                        end_lnum = result.locations[1].physicalLocation.region.startLine - 1,
                                        end_col = result.locations[1].physicalLocation.region.endColumn,
                                        source = "radar",
                                        message = message,
                                        severity = severity,
                                        user_data = {
                                            rule_id = result.ruleId,
                                            details = details,
                                            rule_details = {
                                                precision = rule.properties.precision,
                                                security_severity = rule.properties["security-severity"]
                                            }
                                        }
                                    }
                                    table.insert(diags, diag)
                                    ::continue::
                                end
                            end

                            -- Schedule diagnostic updates
                            vim.schedule(function()
                                local namespace = vim.api.nvim_create_namespace("radar-nvim")
                                vim.diagnostic.set(namespace, params.bufnr, diags)
                            end)
                        end)
                    end)
            end
        }
    }

    null_ls.register(radar_generator)
end

function M.show_rule_details()
    local cursor_pos = vim.api.nvim_win_get_cursor(0)
    local line = cursor_pos[1] - 1
    local col = cursor_pos[2]
    local diagnostics = vim.diagnostic.get(0, {
        namespace = vim.api.nvim_create_namespace("radar-nvim"),
        lnum = line
    })

    local current_diagnostic = nil
    for _, diagnostic in ipairs(diagnostics) do
        if diagnostic.col <= col and col <= diagnostic.end_col then
            current_diagnostic = diagnostic
            break
        end
    end

    if not current_diagnostic or not current_diagnostic.user_data then
        vim.notify("No radar diagnostic found under cursor", vim.log.levels.WARN)
        return
    end

    local details = {
        string.format("Rule ID: %s", current_diagnostic.user_data.rule_id or "N/A"),
        string.format("Message: %s", current_diagnostic.user_data.message or "N/A"),
        string.format("Precision: %s", current_diagnostic.user_data.rule_details.precision or "N/A"),
        string.format("Security Severity: %s", current_diagnostic.user_data.rule_details.security_severity or "N/A")
    }

    vim.lsp.util.open_floating_preview(
        details,
        'markdown',
        {
            border = "rounded",
            focus = true,
            width = 80,
            height = #details,
            close_events = { "BufHidden", "BufLeave" },
            focusable = true,
            focus_id = "radar_details",
        }
    )
end

return M
