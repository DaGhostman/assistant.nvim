local util = require("assistant.util")

---@class assistant.SurroundProvider
---@field name string
---@field add string
---@field delete string
---@field change string

--- The installed surround plugin, if any.
---@param opts assistant.RuleConfig
---@return assistant.SurroundProvider?
local function provider(opts)
  local want = opts.provider
  if want == "nvim-surround" or (want == nil and package.loaded["nvim-surround"]) then
    return { name = "nvim-surround", add = "ys", delete = "ds", change = "cs" }
  end
  if want == "mini.surround" or (want == nil and package.loaded["mini.surround"]) then
    local m = vim.tbl_get(_G, "MiniSurround", "config", "mappings") or {}
    return { name = "mini.surround", add = m.add or "sa", delete = m.delete or "sd", change = m.replace or "sr" }
  end
end

--- Brackets are named by their closing char (`ysiw)` = no inner spaces).
---@param open string
local function target(open)
  return util.PAIRS[open] == open and open or util.PAIRS[open]
end

local NO_PLUGIN = "→ A surround plugin makes this one command: nvim-surround (`ys`/`ds`/`cs`) or mini.surround (`sa`/`sd`/`sr`)"

--- Adding, deleting or changing surrounding quotes/brackets one character at a time.
---@type assistant.Rule
return {
  name = "surround",
  desc = "Adding or removing quotes/brackets by hand",
  check = function(history, opts)
    local last = history[#history]
    if not last or last.is_repeat then
      return
    end
    local p = provider(opts)
    local recent = function(pred)
      return util.find_back(history, function(ev)
        return pred(ev) and ev.buf == last.buf and ev.pos[1] == last.pos[1]
      end, #history, 40)
    end

    -- Add: two single-character inserts that form a pair, around some text.
    if last.key == "<Insert>" and not last.multiline and last.removed == "" and vim.fn.strchars(last.inserted) == 1 then
      local first = recent(function(ev)
        return ev.key == "<Insert>" and not ev.multiline and ev.removed == "" and vim.fn.strchars(ev.inserted) == 1
      end)
      if not first or util.PAIRS[first.inserted] ~= last.inserted or last.pos[2] <= first.pos[2] then
        return
      end
      local line = util.get_line(last.buf, last.pos[1]) or ""
      local inside = line:sub(first.pos[2] + #first.inserted + 1, last.pos[2])
      if inside == "" then
        return
      end
      local motion = inside:match("^[%w_]+$") and "iw" or not inside:find("%s") and "iW" or "{motion}"
      local open = first.inserted
      local msg = ("You wrapped `%s` in `%s…%s` by hand."):format(inside, open, util.PAIRS[open])
      if p then
        return { msg = ("%s\n→ `%s%s%s` does it in one go (%s)"):format(msg, p.add, motion, target(open), p.name) }
      end
      return {
        msg = ('%s\n→ Built in: `c%s%s<C-r>"%s<Esc>` (change it, then paste it back between the pair)\n%s'):format(
          msg,
          motion,
          open,
          util.PAIRS[open],
          NO_PLUGIN
        ),
      }
    end

    -- Delete: two single-character deletes that form a pair.
    if last.key == "<Yank>" and last.operator == "d" and not last.visual and vim.fn.strchars(last.text) == 1 then
      local first = recent(function(ev)
        return ev.key == "<Yank>" and ev.operator == "d" and not ev.visual and vim.fn.strchars(ev.text) == 1
      end)
      local open = first and util.pair_of(first.text, last.text)
      if not open then
        return
      end
      local msg = ("You deleted the `%s…%s` around some text one character at a time."):format(open, util.PAIRS[open])
      if p then
        return { msg = ("%s\n→ `%s%s` removes both at once (%s)"):format(msg, p.delete, target(open), p.name) }
      end
      return { msg = msg .. "\n" .. NO_PLUGIN }
    end

    -- Change: `r` on both characters of a pair.
    if last.arg_of == "r" and last.replaced then
      local first = recent(function(ev)
        return ev ~= last and ev.arg_of == "r" and ev.replaced ~= nil
      end)
      if not first then
        return
      end
      local old = util.pair_of(first.replaced, last.replaced)
      local new = util.pair_of(first.key, last.key)
      if not old or not new then
        return
      end
      local msg = ("You replaced `%s…%s` with `%s…%s` one character at a time."):format(old, util.PAIRS[old], new, util.PAIRS[new])
      if p then
        return {
          msg = ("%s\n→ `%s%s%s` swaps both at once (%s)"):format(msg, p.change, target(old), target(new), p.name),
        }
      end
      return { msg = msg .. "\n" .. NO_PLUGIN }
    end
  end,
}
