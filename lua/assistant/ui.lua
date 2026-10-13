local M = {}

---@class assistant.Highlight
---@field line integer 0-based
---@field col integer
---@field end_col integer
---@field group string

--- Show lines in a centered floating window; `q` / `<Esc>` close it.
---@param lines string[]
---@param hls assistant.Highlight[]
---@param opts { title: string, filetype: string }
function M.float(lines, hls, opts)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  local ns = vim.api.nvim_create_namespace("assistant.ui")
  for _, h in ipairs(hls) do
    vim.api.nvim_buf_set_extmark(buf, ns, h.line, h.col, { end_col = h.end_col, hl_group = h.group })
  end
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = opts.filetype

  local width = 0
  for _, l in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(l))
  end
  width = math.min(width + 2, vim.o.columns - 4)
  local height = math.min(#lines, vim.o.lines - 4)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " " .. opts.title .. " ",
    title_pos = "center",
  })
  vim.wo[win].wrap = false
  for _, key in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", key, function()
      vim.api.nvim_win_close(win, true)
    end, { buffer = buf, nowait = true })
  end
  return buf, win
end

return M
