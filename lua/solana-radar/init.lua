local M = {}

local radar = require('solana-radar.radar')
local config = require('solana-radar.config')

-- Setup function to initialize the plugin
function M.setup(opts)
	if opts then
		for k, v in pairs(opts) do
			M.config[k] = v
		end
	end

	config.setup()
	config.setup_keymaps()
	-- config.print_config()

	if config.config.enabled then
		radar.scan()
	end
end

-- Re-export the config for other modules to use
M.config = config

return M
