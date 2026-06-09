# zsh-vim-mode

A fork of [oh-my-zsh's `vi-mode` plugin](https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/vi-mode),
focused on making **prompt redraws on mode changes reliable and well-behaved**.

It is a drop-in replacement: every public variable and function from omz
`vi-mode` is preserved (`vi_mode_prompt_info`, `MODE_INDICATOR`,
`VI_MODE_SET_CURSOR`, the cursor variables, the key bindings, clipboard
integration, etc.).

## What's different from omz vi-mode

### 1. Mode changes redraw the prompt by default

Upstream only redrew the prompt if it could detect — via an exact substring
match for `'$(vi_mode_prompt_info)'` in `$PS1`/`$RPS1` — that you were showing
the mode in the prompt. That detection is brittle (themes that build the prompt
in `precmd`, store the indicator in a variable, or call the function any other
way all slip past it), so redraws frequently failed to happen.

Here, `VI_MODE_RESET_PROMPT_ON_MODE_CHANGE` defaults to `true`: every switch
between insert / normal / visual issues `zle reset-prompt; zle -R`, so the
prompt indicator and cursor always reflect the current mode.

> `zle reset-prompt` re-expands `$PROMPT`/`$RPROMPT` but does **not** re-run
> `precmd`. For the common pattern of computing expensive things (git status,
> etc.) in `precmd` and storing them in a variable, the redraw is cheap. It is
> only costly if you embed `$(slow-command)` directly inside `$PROMPT`.

### 2. Hooks compose instead of clobbering

Upstream installed its ZLE hooks with raw `zle -N zle-keymap-select`
(and `zle-line-init` / `zle-line-finish`). Those widget names are shared with
zsh-autosuggestions, zsh-syntax-highlighting, powerlevel10k, and others —
whoever loads **last** wins, and the others' hooks silently stop firing
(including, often, the redraw you wanted).

This plugin registers via `add-zle-hook-widget` (with a fallback to raw
`zle -N` on zsh < 5.3). Multiple plugins' hooks coexist. It even absorbs a
pre-existing raw widget from an older plugin and runs both:

```
$ add-zle-hook-widget -L
zstyle zle-keymap-select widgets 0:user:other-plugin-keymap-select 1:vi-mode-keymap-select
```

### 3. Smarter (optional) auto-detection

If you set `VI_MODE_RESET_PROMPT_ON_MODE_CHANGE=auto`, the plugin redraws only
when the prompt actually contains the mode indicator — matching the loose
substring `vi_mode_prompt_info` rather than the exact `$(...)` form, so it
still fires when a theme calls the function indirectly.

## Install

### Manual

```zsh
git clone <this-repo> ~/.zsh/zsh-vim-mode
echo 'source ~/.zsh/zsh-vim-mode/zsh-vim-mode.plugin.zsh' >> ~/.zshrc
```

Source it **after** other plugins that touch `zle-keymap-select` /
`zle-line-init` / `zle-line-finish` so it can absorb their widgets.

### oh-my-zsh

Clone into your custom plugins dir and replace `vi-mode` in your plugin list:

```zsh
git clone <this-repo> "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-vim-mode"
# plugins=(... zsh-vim-mode)   # remove the stock `vi-mode`
```

Loading both the stock `vi-mode` and this plugin is not recommended; this one
replaces it.

## Settings

- `VI_MODE_RESET_PROMPT_ON_MODE_CHANGE` — `true` (default) always redraw on mode
  change; `auto` redraw only if the prompt shows the mode indicator; any other
  value disables redraws.
- `VI_MODE_SET_CURSOR` — set to `true` to change the cursor shape per mode
  (default: unset).
- `VI_MODE_CURSOR_NORMAL` / `_VISUAL` / `_INSERT` / `_OPPEND` — cursor shapes
  (see [Cursor styles](#cursor-styles)).
- `MODE_INDICATOR` / `INSERT_MODE_INDICATOR` — the strings shown in normal /
  insert mode. Support prompt-expansion sequences.
- `VI_MODE_DISABLE_CLIPBOARD` — if set, disables clipboard integration on
  yank/paste.

## Showing the mode in your prompt

`vi_mode_prompt_info` emits the current mode indicator. If neither `$RPS1` nor
`$RPROMPT` is set when the plugin loads, it defaults `RPS1` to show it. To place
it yourself:

```zsh
PROMPT="$PROMPT"'$(vi_mode_prompt_info)'
RPROMPT='$(vi_mode_prompt_info)'"$RPROMPT"
```

The single quotes are important: they defer evaluation so the indicator is
recomputed on each redraw.

## Cursor styles

```zsh
VI_MODE_SET_CURSOR=true
# defaults
VI_MODE_CURSOR_NORMAL=2   # solid block
VI_MODE_CURSOR_VISUAL=6   # solid line
VI_MODE_CURSOR_INSERT=6   # solid line
VI_MODE_CURSOR_OPPEND=0   # blinking block
```

`0,1` blinking block · `2` solid block · `3` blinking underline ·
`4` solid underline · `5` blinking line · `6` solid line.
See [DECSCUSR](https://vt100.net/docs/vt510-rm/DECSCUSR).

## Key bindings

`ESC` or `CTRL-[` enters normal mode. The plugin also binds:

- `vv` (normal mode) — edit the current command line in `$EDITOR`
- `ctrl-p` / `ctrl-n` — previous / next history
- `ctrl-r` / `ctrl-s` — incremental history search backward / forward
- `ctrl-a` / `ctrl-e` — beginning / end of line
- `ctrl-h` / `ctrl-w` / `ctrl-?` — delete char / word / char before cursor
- `v` (normal mode) — visual mode

Yank/delete/change copy to the system clipboard; `p`/`P` paste from it (unless
`VI_MODE_DISABLE_CLIPBOARD` is set).

### Low `$KEYTIMEOUT`

A low `$KEYTIMEOUT` (< 15) makes multi-key bindings like `vv` hard to trigger.
Raise `$KEYTIMEOUT`, or rebind, e.g. `bindkey -M vicmd 'V' edit-command-line`.

## License

MIT, inheriting from oh-my-zsh. See [LICENSE](LICENSE).
