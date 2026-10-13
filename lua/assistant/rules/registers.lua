local util = require("assistant.util")

---@param ev assistant.Event
local function is_yank(ev)
  return ev.key == "<Yank>" and ev.operator == "y" and ev.regname == ""
end

--- A delete or change that overwrote the unnamed register.
---@param ev assistant.Event
local function is_clobber(ev)
  return ev.key == "<Yank>" and (ev.operator == "d" or ev.operator == "c") and ev.regname == ""
end

---@param text string
local function short(text)
  text = text:gsub("\n", "⏎")
  return vim.fn.strchars(text) > 20 and vim.fn.strcharpart(text, 0, 20) .. "…" or text
end

--- Was this delete caused by pasting over a visual selection?
---@param history assistant.Event[]
---@param index integer
local function from_visual_paste(history, index)
  local key = util.recent(history, 1, index)[1]
  return key ~= nil and (key.key == "p" or key.key == "P") and util.is_visual(key.mode)
end

local KEEP_YANK = '→ `"0p` always pastes your last yank, even after deletes'
local BLACK_HOLE = '→ `"_d{motion}` / `"_c` / `"_x` delete into the black hole register and leave your yank alone'
local VISUAL_P = "→ `P` in visual mode replaces the selection without overwriting the register, so you can paste it again and again"

--- Deletes that overwrite what you were about to paste.
---@type assistant.Rule
return {
  name = "registers",
  desc = "Deletes overwriting what you wanted to paste",
  check = function(history)
    local last = history[#history]
    if not last then
      return
    end

    -- yank → delete → `p` pasted the deleted text → `u`
    if last.key == "u" and util.is_plain(last) then
      local keys = util.recent(history, 3)
      local paste, before = keys[2], keys[1]
      if not paste or (paste.key ~= "p" and paste.key ~= "P") or paste.arg or (before and before.arg_of == '"') then
        return
      end
      local _, paste_index = util.find_back(history, function(ev)
        return ev == paste
      end)
      local clobber, ci = util.find_back(history, function(ev)
        return ev.key == "<Yank>"
      end, paste_index)
      if clobber and is_clobber(clobber) and util.find_back(history, is_yank, ci) then
        local tip = from_visual_paste(history, ci) and VISUAL_P or BLACK_HOLE
        return {
          msg = "`p` pasted what you just deleted, not what you yanked.\n" .. KEEP_YANK .. "\n" .. tip,
        }
      end
      return
    end

    -- yank A → (delete or paste over a selection) → yank A again
    if is_yank(last) and not last.is_repeat then
      local clobbered, by_visual = false, false
      for i = #history - 1, 1, -1 do
        local ev = history[i]
        if is_clobber(ev) then
          clobbered = true
          by_visual = by_visual or from_visual_paste(history, i)
        elseif is_yank(ev) then
          if not clobbered or ev.text ~= last.text then
            return
          end
          local msg = ("You yanked `%s` again because it got overwritten.\n"):format(short(last.text))
          return { msg = msg .. (by_visual and VISUAL_P or BLACK_HOLE) .. "\n" .. KEEP_YANK }
        end
      end
    end
  end,
}
