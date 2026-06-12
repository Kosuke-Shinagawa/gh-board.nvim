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
  -- allow injected test globals
  globals = { "describe", "it", "before_each", "after_each", "assert", "pending" },
}
