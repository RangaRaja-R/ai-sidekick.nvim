# ai-sidekick.nvim

Interact with your preferred AI CLI directly from Neovim, with less context switching and faster day-to-day workflows.

## Why I Made This

I wanted a seamless way to interact with the AI when using nvim, the AI IDEs and Apps did not suit for this since it required constant app switching.
The AI CLIs where better, but I could not properly send the context, managing it was a bit difficult and it introduced friction in my workflow.
So I built this, **ai-sidekick**. This will help you interact with the AI CLIs in a better way.

## Core Ideas

- `internal`: keep everything inside Neovim for quick loops.
- `external`: keep AI as a separate long-running entity you can keep using outside the editor pane.
- provider-based setup gives modularity and makes it easy to add more AI CLIs and terminal providers over time.
- send file references or line-range references when you want targeted context.

## Quick Start

### Install

#### `lazy.nvim`

```lua
{
  "rangaraja-r/ai-sidekick.nvim",
  config = function()
    require("ai-sidekick").setup({})
  end,
}
```

#### `packer.nvim`

```lua
use({
  "rangaraja-r/ai-sidekick.nvim",
  config = function()
    require("ai-sidekick").setup({})
  end,
})
```

### Use (Simple)

```lua
require("ai-sidekick").setup({
  default_provider = "codex",
  mode = "internal",
})
```

Start with:

- `<leader>ai` to resume AI
- `<leader>ao` to send current file reference
- visual `<leader>ai` to send selected range reference

### Shortcut Syntax

```lua
require("ai-sidekick").setup({
  shortcuts = {
    r = {
      prompt = "Review the staged changes for bugs, mistakes, and irrelevant changes.",
      mode = "internal", -- internal | external | temporary
      desc = "Review staged changes",
    },
  },
})
```

This creates:

- keymap: `<leader>ar`
- command: `:AI r`

## Keymaps and Commands

| Keymap / Command                           | Mode   | Action                                                 |
| ------------------------------------------ | ------ | ------------------------------------------------------ |
| `<leader>ai` / `:AISidekickResume`         | normal | Open/resume AI                                         |
| `<leader>ai` / `:AISidekickResume`         | visual | Send `relative/path:start-end` reference to resumed AI |
| `<leader>ao` / n/a                         | normal | Open AI with current file reference                    |
| `<leader>ay` / n/a                         | normal | Copy current file reference                            |
| `<leader>ay` / n/a                         | visual | Copy selected range reference                          |
| `<leader>a/` / n/a                         | normal | Open AI in internal mode                               |
| `<leader>an` / `:AISidekickNewChat`        | normal | Open a new chat                                        |
| `<leader>al` / `:AISidekickListChats`      | normal | List chats / pick one (provider-specific)              |
| `<leader>ax` / `:AISidekickToggleMode`     | normal | Toggle `internal` / `external`                         |
| `<leader>ap` / `:AISidekickSelectProvider` | normal | Choose active provider                                 |
| `<leader>a{key}` / `:AI {key}`             | normal | Run configured shortcut from `shortcuts`               |
| n/a / `:AISidekickAsk`                     | normal | Ask for prompt input and run                           |

## Full Configuration

```lua
require("ai-sidekick").setup({
  default_provider = "codex",
  current_provider = nil,
  mode = "internal", -- internal | external

  keymaps = {
    open = "<leader>ai",
    open_internal = "<leader>a/",
    open_with_file = "<leader>ao",
    copy_reference = "<leader>ay",
    new_chat = "<leader>an",
    list_chats = "<leader>al",
    toggle_mode = "<leader>ax",
    select_provider = "<leader>ap",
  },

  window = {
    type = "split", -- split | float
    position = "bottom", -- left | right | top | bottom
    size = 0.33,
    float = {
      width = 0.8,
      height = 0.8,
      border = "rounded",
    },
  },

  external = {
    provider = "kitty",
    send_delay_ms = 500,
    send_enter = false,
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

### AI Provider Examples

Use this only when you want to override built-ins or add your own AI CLI provider.
If your provider is generally useful, feel free to contribute it.

```lua
providers = {
  codex = {
    cmd = "codex",
    args = {},
    prompt_arg = nil,
    temporary_args = { "exec", "--ephemeral" },
    resume_args = { "resume", "--last" },
    list_args = { "resume" },
  },
  cursor = {
    cmd = "cursor",
    args = { "agent" },
    prompt_arg = nil,
    temporary_args = { "agent", "-p" },
    resume_args = { "agent", "resume" },
    list_args = { "agent", "ls" },
  },
  claude = {
    cmd = "claude",
    args = {},
    prompt_arg = nil,
    temporary_args = {},
    resume_args = {},
    list_args = {},
  },
}
```

### Provider Fields

- `cmd`: executable name
- `args`: extra base args
- `prompt_arg`: optional flag used before prompt in external mode
- `temporary_args`: args used by `temporary` mode
- `resume_args`: args used by resume flow
- `list_args`: args used by list chats flow

## Requirements

### Kitty (for external mode)

Kitty remote control must be enabled.

`kitty.conf`:

```conf
allow_remote_control yes
listen_on unix:/tmp/kitty-{kitty_pid}.sock
```

## Contributing

Provider contributions are welcome.

- AI providers: `lua/ai-sidekick/providers/AI/`
- Terminal providers: `lua/ai-sidekick/providers/terminal/`

For provider PRs, include:

- provider implementation
- dependency notes (CLI/terminal requirements)
- behavior notes for resume/list/new-chat support

For feature requests or bug reports, open an issue.

## How External Mode Works

External mode is terminal-provider-driven. The default implementation uses Kitty remote control.

When reopening in the same project, ai-sidekick tries to reattach before opening a new tab.

Reattach order:

1. Prefer tabs/windows tagged with `AI_SIDEKICK_ROOT=<project_root>` (set during launch via `kitty @ launch --var`).
2. Fallback for older tabs:
   - match project root from `foreground_processes[].cwd` or `window.cwd`
   - require foreground process command line to match the active provider command.
3. If multiple matches remain:
   - prefer titles containing `ai-sidekick`
   - then active tabs
   - then newer windows.

## What's Next

- Forward diagnostics and errors to the AI.
- Send selected content, including diagnostics, through shortcuts.
- Add temporary mode to core usage for one-off, stateless prompts.

## Notes

- Relative paths are computed from git root when `.git` exists, otherwise from current working directory.
- Internal mode prefills prompt/reference text and does not auto-submit.
- External text injection behavior depends on terminal provider capabilities.
- Resume/list behavior depends on provider support (`resume_args`, `list_args`).
