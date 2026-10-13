local util = require("assistant.util")

--- Multi-key sequences that have a dedicated, shorter command.
--- All keys are pressed in normal mode, unless `insert_first` is set.
local SEQUENCES = {
  { keys = { "$", "a" }, use = "A", what = "appends at the end of the line" },
  { keys = { "^", "i" }, use = "I", what = "inserts before the first non-blank character" },
  { keys = { "0", "i" }, use = "I", what = "inserts before the first non-blank (`gI` for column 0)" },
  { keys = { "d", "$" }, use = "D", what = "deletes to the end of the line" },
  { keys = { "c", "$" }, use = "C", what = "changes to the end of the line" },
  { keys = { "y", "$" }, use = "Y", what = "yanks to the end of the line" },
  { keys = { "D", "a" }, use = "C", what = "deletes to the end of the line and starts inserting" },
  { keys = { "D", "A" }, use = "C", what = "deletes to the end of the line and starts inserting" },
  { keys = { "x", "i" }, use = "s", what = "deletes the character and starts inserting" },
  { keys = { "d", "w", "i" }, use = "cw", what = "changes the word" },
  { keys = { "d", "e", "i" }, use = "ce", what = "changes to the end of the word" },
  { keys = { "d", "d", "O" }, use = "cc", what = "replaces the whole line (keeps indentation)" },
  { keys = { "b", "c", "w" }, use = "ciw", what = "changes the whole word from anywhere inside it" },
  { keys = { "b", "c", "e" }, use = "ciw", what = "changes the whole word from anywhere inside it" },
  { keys = { "b", "d", "w" }, use = "daw", what = "deletes the word and its space from anywhere inside it" },
  { keys = { "b", "y", "w" }, use = "yiw", what = "yanks the word from anywhere inside it" },
  { keys = { "b", "v", "e" }, use = "viw", what = "selects the word from anywhere inside it" },
  { keys = { "<Esc>", "p", "a" }, use = '<C-r>"', what = "pastes without leaving insert mode", insert_first = true },
  { keys = { "<Esc>", "p", "i" }, use = '<C-r>"', what = "pastes without leaving insert mode", insert_first = true },
  { keys = { "<Esc>", "u", "a" }, use = "<C-u>", what = "deletes what you typed on the line, still in insert mode", insert_first = true },
}

---@type assistant.Rule
return {
  name = "shortcuts",
  desc = "Two-key combos with a one-key command",
  check = function(history)
    if not history[#history] or util.is_side(history[#history]) then
      return
    end
    for _, seq in ipairs(SEQUENCES) do
      local len = #seq.keys
      local events = util.recent(history, len)
      local match = #events == len
      for i, ev in ipairs(events) do
        local mode_ok = (i == 1 and seq.insert_first) and util.is_insert(ev.mode) or ev.mode:sub(1, 1) == "n"
        if not match or ev.key ~= seq.keys[i] or ev.arg or ev.count_digit or not mode_ok then
          match = false
          break
        end
      end
      if match then
        local keys = #seq.use:gsub("<[^>]+>", "x")
        return {
          msg = ("You typed `%s`.\n→ `%s` %s (%s instead of %d)"):format(
            table.concat(seq.keys),
            seq.use,
            seq.what,
            util.plural(keys, "key"),
            len
          ),
        }
      end
    end
  end,
}
