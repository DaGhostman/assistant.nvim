---@class assistant.Rule
---@field name string
---@field desc string Short description of the habit, for the report
---@field check fun(history: assistant.Event[], opts: assistant.RuleConfig): assistant.Hint?

-- Order is priority: when several hints are pending, the first one wins.
---@type assistant.Rule[]
return {
  -- Moving around
  require("assistant.rules.jumps"),
  require("assistant.rules.vertical"),
  require("assistant.rules.horizontal"),
  require("assistant.rules.search"),
  -- Editing
  require("assistant.rules.shortcuts"),
  require("assistant.rules.registers"),
  require("assistant.rules.textobjects"),
  require("assistant.rules.surround"),
  require("assistant.rules.comments"),
  require("assistant.rules.selections"),
  require("assistant.rules.substitute"),
  -- Repetition
  require("assistant.rules.repeat"),
  require("assistant.rules.macro"),
  require("assistant.rules.repeats"),
  -- Basics
  require("assistant.rules.arrows"),
  require("assistant.rules.backspace"),
  require("assistant.rules.commands"),
}
