local M = {}

---@class assistant.RuleConfig
---@field enabled? boolean
---@field threshold? integer Minimum repetitions before the rule triggers
---@field cooldown? integer Seconds before this rule may show again (overrides `cooldown.rule`)
---@field provider? string Surround plugin to suggest (`surround` rule only)

---@class assistant.LearnConfig
---@field enabled boolean
---@field focus_count integer Skills to focus on per day
---@field daily_goal integer Uses of the focus skill per day
---@field learned_uses integer Uses (within `window_days`) before a skill counts as learned
---@field learned_days integer Different days it must be used on
---@field window_days integer
---@field relapse_threshold integer Habits noticed within `relapse_days` that count as a relapse
---@field relapse_days integer
---@field quiet_learned boolean Stop hints for habits whose skills are learned
---@field announce boolean Show today's focus once a day
---@field announce_delay integer Milliseconds after startup before the announcement
---@field path? string

---@class assistant.Config
---@field enabled boolean Start tracking as soon as `setup()` is called
---@field delay integer Milliseconds without keypresses before a pending hint is shown
---@field streak_gap integer Milliseconds between two keys before a streak (`jjjj`) is considered over
---@field display_time? integer Milliseconds a hint stays visible (passed as `timeout` to `vim.notify`)
---@field cooldown { global: integer, rule: integer } Seconds between any two hints / repeats of the same hint
---@field excluded_filetypes string[]
---@field excluded_buftypes string[]
---@field debug boolean Report errors inside rules (they are silently ignored otherwise)
---@field display "notify"|"ghost"|"both" Where hints appear: notifications, virtual text at the cursor line, or both
---@field ghost { live: boolean, live_after: integer, max_lines: integer }
---@field stats { enabled: boolean, path?: string, save_interval: integer, keep_days: integer, report_days: integer }
---@field learn assistant.LearnConfig
---@field notify? fun(msg: string, hint: assistant.Hint) Custom display function (defaults to `vim.notify`)
---@field rules table<string, assistant.RuleConfig>
M.defaults = {
  enabled = true,
  delay = 1000,
  streak_gap = 1000,
  display_time = 5000,
  cooldown = {
    global = 30,
    rule = 180,
  },
  excluded_filetypes = {
    "help",
    "lazy",
    "mason",
    "neo-tree",
    "NvimTree",
    "oil",
    "TelescopePrompt",
    "snacks_picker_input",
    "minifiles",
    "fzf",
  },
  excluded_buftypes = { "nofile", "prompt", "terminal", "quickfix" },
  display = "notify",
  ghost = {
    live = true, -- show motion targets while you repeat h/j/k/l
    live_after = 2, -- presses before the targets appear
    max_lines = 20, -- lines labelled for j/k
  },
  stats = {
    enabled = true, -- save daily counts for :Assistant report
    path = nil, -- defaults to stdpath("data") .. "/assistant/stats.json"
    save_interval = 300, -- seconds between saves (also saved on exit)
    keep_days = 120,
    report_days = 7, -- period the report compares
  },
  learn = {
    enabled = true,
    focus_count = 1, -- skills to focus on per day
    daily_goal = 10, -- uses of the focus skill per day
    learned_uses = 15, -- a skill is learned after this many uses …
    learned_days = 3, -- … on at least this many different days …
    window_days = 30, -- … within this many days
    relapse_threshold = 5, -- the old habit noticed this often …
    relapse_days = 3, -- … within this many days brings the skill back into focus
    quiet_learned = true, -- stop hints for habits whose skills are learned
    announce = true, -- show today's focus once a day
    announce_delay = 1500,
    path = nil, -- defaults to stdpath("data") .. "/assistant/learn.json"
  },
  notify = nil,
  debug = false,
  rules = {
    -- Moving around
    jumps = { enabled = true, threshold = 3 },
    vertical = { enabled = true, threshold = 4 },
    horizontal = { enabled = true, threshold = 4 },
    search = { enabled = true },
    -- Editing
    shortcuts = { enabled = true },
    registers = { enabled = true },
    textobjects = { enabled = true },
    surround = { enabled = true, provider = nil }, -- "nvim-surround" | "mini.surround" | nil (auto-detect)
    comments = { enabled = true },
    selections = { enabled = true, threshold = 3 },
    substitute = { enabled = true, threshold = 3 },
    -- Repetition
    ["repeat"] = { enabled = true },
    macro = { enabled = true, threshold = 3 },
    repeats = { enabled = true, threshold = 4 },
    -- Basics
    arrows = { enabled = true, threshold = 2 },
    backspace = { enabled = true, threshold = 6 },
    commands = { enabled = true },
  },
}

---@type assistant.Config
M.options = vim.deepcopy(M.defaults)

---@param opts? table
function M.set(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

---@param name string
---@return assistant.RuleConfig
function M.rule(name)
  return M.options.rules[name] or {}
end

return M
