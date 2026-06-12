-- vim globals
globals = {
  "vim",
}

-- plenary / nui globals exposed at test time
read_globals = {
  "describe",
  "it",
  "before_each",
  "after_each",
  "assert",
  "pending",
}

-- ignore line-length warnings (stylua handles formatting)
max_line_length = false

-- ignore unused self in methods
self = false

files["tests/**/*.lua"] = {
  globals = { "describe", "it", "before_each", "after_each", "assert", "pending" },
  -- allow monkey-patching os and vim in tests
  read_globals = {},
  ignore = { "122" },  -- W122: setting read-only field of global
}
