-- Lua wrapper for standalone tool
-- This provides a Neutrino menu entry that calls your external tool
--
-- Replace "my-tool" with your actual tool name

local posix = require("posix")

-- Configuration
local TOOL_NAME = "my-tool"
local TOOL_PATH = "/usr/bin/my-tool"
local TOOL_TITLE = "My Tool"

-- Helper function: Check if tool is installed
local function check_tool()
	local handle = io.popen("command -v " .. TOOL_PATH .. " 2>/dev/null")
	local result = handle:read("*a")
	handle:close()
	return result ~= ""
end

-- Helper function: Show message
local function show_message(title, text, icon)
	icon = icon or "info"
	local msg = {
		title = title,
		text = text,
		icon = icon
	}
	neutrino.ShowMsg(msg)
end

-- Helper function: Run tool with options
local function run_tool(args)
	args = args or ""

	-- Check if tool exists
	if not check_tool() then
		show_message(
			TOOL_TITLE,
			"Tool not installed: " .. TOOL_PATH,
			"error"
		)
		return false
	end

	-- Show info message
	show_message(
		TOOL_TITLE,
		"Running " .. TOOL_NAME .. "...\nPlease wait.",
		"info"
	)

	-- Execute tool
	local cmd = TOOL_PATH .. " " .. args
	local ret = os.execute(cmd)

	-- Check result
	if ret == 0 then
		show_message(
			TOOL_TITLE,
			TOOL_NAME .. " completed successfully",
			"info"
		)
		return true
	else
		show_message(
			TOOL_TITLE,
			TOOL_NAME .. " failed with error code: " .. tostring(ret),
			"error"
		)
		return false
	end
end

-- Main plugin function
local function main()
	-- Simple example: Just run the tool
	run_tool()

	-- Advanced example with menu:
	-- local n_gui = require("n_gui")
	-- local menu = n_gui.menu.new(TOOL_TITLE, "info")
	-- menu:addItem{type = "forwarder", name = "Run Tool", action = "lua", id = "run"}
	-- menu:addItem{type = "forwarder", name = "Run with Verbose", action = "lua", id = "verbose"}
	-- local selected = menu:exec()
	-- if selected == "run" then
	--     run_tool()
	-- elseif selected == "verbose" then
	--     run_tool("--verbose")
	-- end
end

-- Return plugin interface
return {
	run = main,
	name = TOOL_TITLE,
	version = "1.0.0"
}
