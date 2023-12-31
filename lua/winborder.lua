local api = vim.api
local fn = vim.fn

local M = {}

---@param hlgroup_name  string
---@param attr  '"fg"' | '"bg"'
---@return string Hex color
local get_hex = function(hlgroup_name, attr)
	local hlgroup_ID = fn.synIDtrans(fn.hlID(hlgroup_name))
	local hex = fn.synIDattr(hlgroup_ID, attr)
	return hex ~= "" and hex or "NONE"
end

---@field buf buffer
M.buf = nil

---@field win window
M.win = nil

---@class WinBorder.Config
M.config = {
	---@alias Winborder.Highlight { fg: string, bg: string }
	hl = {
		---@type string
		fg = nil,
		---@type string
		bg = nil,
	},
	---@type boolean
	enable_on_startup = nil,
}

---@param o WinBorder.Config
function M.setup(o)
	M.config = vim.tbl_deep_extend("force", {
		hl = {
			fg = get_hex("TabLineSel", "bg"),
			bg = get_hex("Normal", "bg"),
		},
		enable_on_startup = true,
	}, o or {})
	M.create_highlight()

	if M.config.enable_on_startup then
		M.enable()
	end
end

function M.create_buffer()
	if M.buf == nil then
		M.buf = api.nvim_create_buf(false, false)
		api.nvim_buf_set_option(M.buf, "buftype", "nofile")
		api.nvim_buf_set_option(M.buf, "swapfile", false)
		api.nvim_buf_set_option(M.buf, "buflisted", false)
		api.nvim_buf_set_option(M.buf, "filetype", "")
		api.nvim_buf_set_option(M.buf, "modifiable", false)
	end
end

M.enabled = false

function M.enable()
	M.create_autocmds()
	M.create_buffer()
	M.create_window()
	M.enabled = true
end

function M.disable()
	M.del_autocmds()
	M.close_window()
	if M.buf ~= nil and api.nvim_buf_is_valid(M.buf) then
		api.nvim_buf_delete(M.buf, { force = true })
		M.buf = nil
	end
	M.enabled = false
end

function M.toggle()
	if M.enabled then
		M.disable()
	else
		M.enable()
	end
end

function M.create_autocmds()
	if not M.autocmds then
		M.autocmds = {}
	end
	M.autocmds[#M.autocmds] = api.nvim_create_autocmd({ "WinLeave", "WinEnter", "WinResized" }, {
		callback = M.update_window,
	})
end

function M.del_autocmds()
	for _, autocmd in ipairs(M.autocmds) do
		api.nvim_del_autocmd(autocmd)
	end
	M.autocmds = {}
end

function M.create_highlight()
	api.nvim_set_hl(0, "SepBorder", M.config.hl)
	api.nvim_set_hl(0, "SepBorderNone", {
		nocombine = true,
		blend = 100,
		bg = "NONE",
		fg = "NONE",
	})
end

function M.create_window()
	local curwin = api.nvim_get_current_win()
	local w, h, row, col, border = M.get_win_config()
	M.win = api.nvim_open_win(M.buf, false, {
		relative = "editor",
		width = w,
		height = h,
		focusable = false,
		row = row,
		col = col,
		style = "minimal",
		zindex = 10,
		border = border,
		noautocmd = true,
	})
	vim.api.nvim_create_autocmd("WinClosed", {
		buffer = M.buf,
		callback = function()
			vim.schedule(function()
				vim.api.nvim_buf_delete(M.buf, { force = true })
			end)
		end,
	})
	api.nvim_win_set_option(M.win, "winhighlight", "FloatBorder:SepBorder")
	api.nvim_win_set_option(M.win, "winblend", 100)
	M.last_win = curwin
end

function M.close_window()
	if M.win ~= nil then
		api.nvim_win_close(M.win, true)
		M.win = nil
	end
	M.last_win = nil
end

function M.update_window()
	-- close if only one window visible
	if M.enabled == false or vim.fn.winlayout()[1] == "leaf" then
		M.close_window()
		return
	end
	local curwin = api.nvim_get_current_win()
	M.last_win = curwin
	if not M.win then
		M.create_window()
	end
	local w, h, row, col, border = M.get_win_config()
	local conf = api.nvim_win_get_config(M.win)
	conf.border = border
	conf.width = w
	conf.height = h
	conf.row = row
	conf.col = col
	api.nvim_win_set_config(M.win, conf)
end

local Border = {
	TopLeft = 1,
	Top = 2,
	TopRight = 3,
	Right = 4,
	BotRight = 5,
	Bot = 6,
	BotLeft = 7,
	Left = 8,
}

function M.get_win_config()
	local curwin = api.nvim_get_current_win()
	local w = api.nvim_win_get_width(curwin)
	local h = api.nvim_win_get_height(curwin)
	local pos = api.nvim_win_get_position(curwin)

	local border = {
		-- "┏",
		-- "━",
		-- "┓",
		-- "┃",
		-- "┛",
		-- "━",
		-- "┗",
		-- "┃",
		{ " ", "SepBorderNone" },
		{ " ", "SepBorderNone" },
		{ " ", "SepBorderNone" },
		{ "┃", "SepBorder" },
		{ " ", "SepBorderNone" },
		{ " ", "SepBorderNone" },
		{ " ", "SepBorderNone" },
		{ "┃", "SepBorder" },
	}
	local dy = 0
	local dx = 0
	local dw = 0
	local dh = 0
	if M.is_top_edge(pos) then
		border[Border.Top] = { " ", "SepBorderNone" }
		border[Border.TopRight] = { "┃", "SepBorder" }
		dh = 1
	else
		border[Border.TopRight] = { "┓", "SepBorder" }
		border[Border.Top] = { "━", "SepBorder" }
	end
	if M.is_bottom_edge(pos, h) then
		border[Border.Bot] = { " ", "SepBorderNone" }
		dy = dh > 0 and 0 or 1
		dh = dh + 1
		border[Border.BotLeft] = { "┃", "SepBorder" }
		border[Border.BotRight] = { "┃", "SepBorder" }
	else
		border[Border.Bot] = { "━", "SepBorder" }
		border[Border.BotLeft] = { "┗", "SepBorder" }
		border[Border.BotRight] = { "┛", "SepBorder" }
	end

	if M.is_left_edge(pos) then
		border[Border.TopLeft] = { " ", "SepBorderNone" }
		dw = 1
		if not M.is_top_edge(pos) then
			border[Border.TopLeft] = { "┏", "SepBorder" }
		end
	else
		border[Border.Left] = { "┃", "SepBorder" }
		if M.is_top_edge(pos) then
			border[Border.TopLeft] = { "┃", "SepBorder" }
		else
			border[Border.TopLeft] = { "┏", "SepBorder" }
		end
	end
	if M.is_right_edge(pos, w) then
		dx = dw > 0 and 0 or 1
		dw = 1
	end

	if dx == 0 and dw == 0 then
		dx = 1
	end
	if dy == 0 and dh == 0 then
		dy = 1
	end

	w = w - dw
	h = h - dh
	local row, col = pos[1] - dy, pos[2] - dx
	return w, h, row, col, border
end

function M.is_left_edge(pos)
	return pos[2] == 0
end

function M.is_right_edge(pos, w)
	local columns = vim.o.columns - 1
	return pos[2] + w >= columns
end

function M.is_top_edge(pos)
	return pos[1] == 1
end

function M.is_bottom_edge(pos, h)
	local lines = vim.o.lines - 1
	return pos[1] + h >= lines
end

--- For users of luukvbaal/statuscol.nvim, use as condition in first
--- section to pad the leftmost window.
function M.statuscol(args)
	return vim.api.nvim_win_get_position(args.win)[2] == 0
end

---@alias WinBorder.Edge "left"|"right"|"top"|"bottom"
---@param win window
---@return WinBorder.Edge[]
-- Determine if a window is on the edge of the screen, returning
-- a list of the edges it's touching.
function M.is_edge(win)
	local res = {}
	local pos = api.nvim_win_get_position(win)
	local w = api.nvim_win_get_width(win)
	local h = api.nvim_win_get_height(win)
	if M.is_left_edge(pos) then
		table.insert(res, "left")
	end
	if M.is_right_edge(pos, w) then
		table.insert(res, "right")
	end
	if M.is_top_edge(pos) then
		table.insert(res, "top")
	end
	if M.is_bottom_edge(pos, h) then
		table.insert(res, "bottom")
	end
	return res
end

return {
	setup = M.setup,
	enable = M.enable,
	disable = M.disable,
	toggle = M.toggle,
	utils = {
		is_edge = M.is_edge,
		statuscol = M.statuscol,
	},
}
