-- Template for a Neutrino Lua Plugin
-- Replace "my-plugin" with your actual plugin name
--
-- This template demonstrates:
-- - Loading shared Lua libraries (json, n_gui)
-- - Creating a simple menu
-- - Basic plugin structure

local json = require("json")
local n_gui = require("n_gui")
local posix = require("posix")

-- Plugin configuration
local PLUGIN_NAME = "My Plugin"
local PLUGIN_VERSION = "1.0.0"

-- Helper function: Show info message
local function show_info(message)
	local msg = {
		text = message,
		title = PLUGIN_NAME,
		icon = "info"
	}
	neutrino.ShowMsg(msg)
end

-- Helper function: Show error message
local function show_error(message)
	local msg = {
		text = message,
		title = PLUGIN_NAME,
		icon = "error"
	}
	neutrino.ShowMsg(msg)
end

-- Main plugin function
local function main()
	-- Create main menu
	local menu = n_gui.menu.new(PLUGIN_NAME .. " v" .. PLUGIN_VERSION, "info")

	-- Add menu items
	menu:addItem{
		type = "forwarder",
		name = "Hello World",
		action = "lua",
		enabled = true,
		directkey = "",
		id = "hello-world",
		hidden = false
	}

	menu:addItem{
		type = "forwarder",
		name = "Show System Info",
		action = "lua",
		enabled = true,
		directkey = "",
		id = "system-info",
		hidden = false
	}

	menu:addItem{
		type = "separatorline",
		enabled = false
	}

	menu:addItem{
		type = "forwarder",
		name = "About",
		action = "lua",
		enabled = true,
		directkey = "",
		id = "about",
		hidden = false
	}

	-- Handle menu selection
	local selected = menu:exec()

	if selected == "hello-world" then
		show_info("Hello from " .. PLUGIN_NAME .. "!")

	elseif selected == "system-info" then
		local info = {}
		info.hostname = posix.uname("%n") or "unknown"
		info.release = posix.uname("%r") or "unknown"
		info.machine = posix.uname("%m") or "unknown"

		local text = string.format(
			"Hostname: %s\nKernel: %s\nArch: %s",
			info.hostname,
			info.release,
			info.machine
		)
		show_info(text)

	elseif selected == "about" then
		local about_text = string.format(
			"%s Version %s\n\n" ..
			"This is a template plugin for Neutrino.\n" ..
			"Customize it to create your own plugin!\n\n" ..
			"License: GPL-2.0-or-later",
			PLUGIN_NAME,
			PLUGIN_VERSION
		)
		show_info(about_text)
	end
end

-- Return plugin interface
return {
	run = main,
	name = PLUGIN_NAME,
	version = PLUGIN_VERSION
}
