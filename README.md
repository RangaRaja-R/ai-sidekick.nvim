# ai-sidekick.nvim

A minimal Neovim plugin for AI CLIs with two execution modes:

- `internal`: run quick tasks in a split inside Neovim
- `external`: open a new terminal outside Neovim for deeper work

The plugin keeps context intentionally small. It only sends relative file references like `src/main.rs`
or `src/main.rs:4-10`. It does not send buffer contents.

It is built with Codex in mind first, but the provider config is intentionally shallow so other CLIs can
be added with the same flow.

Built-in providers:

- `codex`
- `cursor`

## Setup

```lua
require("ai-sidekick").setup({
  default_provider = "codex",
  mode = "internal",
  window = {
    type = "split",
    position = "bottom",
    size = 0.33,
  },
  providers = {
    codex = {
      cmd = "codex",
    },
    cursor = {
      cmd = "cursor",
      args = { "agent" },
      resume_args = { "agent", "resume" },
    },
    claude = {
      cmd = "claude",
    },
    gemini = {
      cmd = "gemini",
    },
  },
  shortcuts = {
    r = {
      prompt = "Review the staged changes for bugs, mistakes, and irrelevant changes.",
      mode = "internal",
      desc = "Review staged changes",
    },
    c = {
      prompt = "Generate a concise commit message for the staged changes.",
      mode = "internal",
      desc = "Generate commit message",
    },
  },
})
```

## Behavior

- Normal `<leader>ao` opens the current mode with no extra context.
- Normal `<leader>aO` sends the current file as a relative reference like `lua/ai-sidekick/init.lua`.
- Visual `<leader>ao` sends only a file reference with line range like `lua/ai-sidekick/init.lua:10-24`.
- Internal mode starts the provider in a split and then prefills the text after a short delay without pressing Enter.
- Internal mode can open either in a split or a floating window.
- External mode launches a new terminal command and passes the prompt/reference through the provider CLI invocation.
- `<leader>ax` resumes the provider session for providers that define resume behavior.

## Default keymaps

- `<leader>ao` in normal mode: open the selected mode with no extra context
- `<leader>aO` in normal mode: open the selected mode with the current file reference
- `<leader>ao` in visual mode: send `relative/path:start-end`
- `<leader>ai`: always open the internal split UI
- `<leader>ax`: resume the provider session in the selected mode
- `<leader>am`: toggle `internal` / `external`
- `<leader>ap`: choose the active provider
- `<leader>ar`, `<leader>ac`, etc: run configured shortcuts from `shortcuts`

## Commands

- `:AISidekickToggleMode`
- `:AISidekickSelectProvider`
- `:AISidekickAsk`
- `:AISidekickResume`
- `:AI {key}` to run a configured shortcut, for example `:AI r`

## Shortcut Prompts

Shortcut prompts are config-driven. Each key under `shortcuts` creates:

- a normal-mode mapping at `<leader>a{key}`
- a command form `:AI {key}`

Example:

```lua
require("ai-sidekick").setup({
  shortcuts = {
    r = {
      prompt = "Review the staged changes for bugs, mistakes, and irrelevant changes.",
      mode = "internal",
      desc = "Review staged changes",
    },
    d = {
      prompt = "Explain the design tradeoffs in this change.",
      mode = "external",
      desc = "Deep design review",
    },
  },
})
```

This gives you:

- `<leader>ar` and `:AI r`
- `<leader>ad` and `:AI d`

## Provider Shape

The provider system is intentionally simple:

```lua
providers = {
  codex = {
    cmd = "codex",
    args = {},
    prompt_arg = nil,
    resume_args = { "resume", "--last" },
  },
  cursor = {
    cmd = "cursor",
    args = { "agent" },
    prompt_arg = nil,
    resume_args = { "agent", "resume" },
  },
}
```

- `cmd`: executable name
- `args`: extra base arguments
- `prompt_arg`: optional flag used before the prompt in external mode
- `resume_args`: optional arguments used by `<leader>ax` / `:AISidekickResume`

## External Terminal

External mode is terminal-configurable and currently defaults to Kitty:

```lua
external = {
  launcher = { "kitty", "@", "launch", "--type=tab", "sh", "-lc" },
}
```

The launcher must accept a final shell command string appended by the plugin. For Kitty remote control,
the user must enable remote control in Kitty config.

## Internal Window

Internal mode supports both splits and floating windows.

Split example:

```lua
window = {
  type = "split",
  position = "right", -- left | right | top | bottom
  size = 0.4, -- ratio or absolute columns/lines
}
```

Float example:

```lua
window = {
  type = "float",
  float = {
    width = 0.8,  -- ratio or absolute columns
    height = 0.8, -- ratio or absolute lines
    border = "rounded",
  },
}
```

## Notes

- Relative paths are computed from the git root when `.git` exists, otherwise from the current working directory.
- Internal mode does not send file contents. It only prepopulates the prompt/reference text and leaves submission to the user.
- For backward compatibility, old `split = {...}` config is still accepted and mapped into `window`.
- External mode is not terminal-agnostic for post-launch text injection. If you want to send text after launch, that needs terminal-specific remote control such as Kitty `send-text`.
- Resume is provider-specific. If a provider does not define `resume_args`, resume will fail with an error.
