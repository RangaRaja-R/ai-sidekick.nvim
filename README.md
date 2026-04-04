# ai-sidekick.nvim (WIP)

A minimal Neovim plugin for AI CLIs with two execution modes:

- `internal`: run quick tasks in a split inside Neovim
- `external`(WIP): open a new terminal outside Neovim for deeper work

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

- Normal `<leader>ai` opens AI in resume mode.
- Visual `<leader>ai` sends only a file reference with line range like `lua/ai-sidekick/init.lua:10-24` to the resumed AI session.
- Normal `<leader>ao` sends the current file as a relative reference like `lua/ai-sidekick/init.lua`.
- Internal mode starts the provider in a split and then prefills the text after a short delay without pressing Enter.
- Internal mode can open either in a split or a floating window.
- External mode uses a persistent external terminal tab. If the tab is already open, the plugin focuses it and sends text into it when supported.
- `<leader>an` forces a new chat instead of resume.
- `<leader>al` opens provider chat listing/picker (provider-specific).

## Default keymaps

- `<leader>ai` in normal mode: open/resume AI
- `<leader>ai` in visual mode: send `relative/path:start-end` reference to resumed AI
- `<leader>ao` in normal mode: send current file reference
- `<leader>a/`: open in internal mode
- `<leader>an`: open a new chat
- `<leader>al`: list chats / pick one (provider-specific)
- `<leader>ax`: toggle `internal` / `external`
- `<leader>ap`: choose the active provider
- `<leader>ar`, `<leader>ac`, etc: run configured shortcuts from `shortcuts`

## Commands

- `:AISidekickToggleMode`
- `:AISidekickSelectProvider`
- `:AISidekickAsk`
- `:AISidekickResume`
- `:AISidekickNewChat`
- `:AISidekickListChats`
- `:AI {key}` to run a configured shortcut, for example `:AI r`

## Shortcut Prompts

Shortcut prompts are config-driven. Each key under `shortcuts` creates:

- a normal-mode mapping at `<leader>a{key}`
- a command form `:AI {key}`
- when `mode` is omitted on a shortcut, it uses the current global plugin mode

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
    list_args = { "resume" },
  },
  cursor = {
    cmd = "cursor",
    args = { "agent" },
    prompt_arg = nil,
    resume_args = { "agent", "resume" },
    list_args = { "agent", "ls" },
  },
}
```

- `cmd`: executable name
- `args`: extra base arguments
- `prompt_arg`: optional flag used before the prompt in external mode
- `resume_args`: optional arguments used by `<leader>ai` / `:AISidekickResume`
- `list_args`: optional arguments used by `<leader>al` / `:AISidekickListChats`

## External Terminal

External mode is terminal-configurable and currently defaults to Kitty:

```lua
external = {
  provider = "kitty", -- or a custom table command set
  send_delay_ms = 500,
  send_enter = false,
  providers = {
    kitty = {}, -- use built-in defaults from providers/terminal/kitty.lua
  },
}
```

External terminal behavior is provided by `providers/terminal/<provider>.lua`. The default provider is
`kitty`, which opens/focuses a persistent tab and sends text through Kitty remote control commands.

You can also pass a custom provider table directly:

```lua
external = {
  provider = {
    check = { "kitty", "@", "ls" },
    list = { "kitty", "@", "ls" },
    launch = { "kitty", "@", "launch", "--type=tab" },
    send_text = { "kitty", "@", "send-text", "--stdin", "--match" },
  },
}
```

Guardrail: custom providers must define at least `check`, `list`, `launch`, and `send_text`.

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
- External text injection is terminal-specific. The current implementation expects the configured terminal commands to behave like Kitty remote control.
- Resume is provider-specific. If a provider does not define `resume_args`, resume will fail with an error.
