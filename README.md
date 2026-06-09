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

### 2. Order-independent; no fighting over contested widgets

Upstream installed its ZLE hooks with raw `zle -N zle-keymap-select`,
`zle-line-init`, and `zle-line-finish`. Those last two are heavily contested:
**oh-my-posh** decorates `zle-line-init` (it runs `.recursive-edit` there),
and **zsh-autosuggestions** / **fast-syntax-highlighting** wrap it as well.
When several wrapping schemes meet on `zle-line-init` in the wrong order, the
wrappers chain into each other and zsh aborts with:

```
_omp_decorated_zle-line-init: maximum nested function level reached; increase FUNCNEST?
```

This plugin sidesteps that entirely. The only zle widget it hooks is
`keymap-select` — the actual mode-change event that drives the redraw — via
`add-zle-hook-widget` (nothing else wraps that widget). Everything omz did in
the `zle-line-init` / `zle-line-finish` *widgets* (reset to insert mode, cursor
shape, keypad mode) is instead done in `precmd` / `preexec`, registered with
`add-zsh-hook`. Those are plain hook arrays with no wrap/absorb semantics, so
the plugin composes with everything and **does not depend on load order** — it
works correctly whether it loads before or after oh-my-posh and the rest.

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

Load order does not matter — source it before or after oh-my-posh,
zsh-autosuggestions, fast-syntax-highlighting, etc.

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
- `VI_MODE_EMACS_INSERT` — set to `true` to make **insert mode behave like the
  normal (emacs/readline) keymap**: arrow keys, alt-word motion, `^A`/`^E`/`^K`/
  `^U`, alt-backspace, history search, etc. `ESC` still drops into vi normal
  mode. The bindings are added to `viins` additively (the keymap is never
  replaced), so this is order-independent and your own later bindings still win.
  See [Emacs-style insert mode](#emacs-style-insert-mode).

## Emacs-style insert mode

By default this is a normal vi-mode: insert mode has only a handful of
conveniences and is otherwise spartan. If you'd rather *type* with the editing
keys you already know and only reach for vi when you press `ESC`, set:

```zsh
VI_MODE_EMACS_INSERT=true
```

Insert mode (`viins`) then gets the standard readline/emacs set — `Left`/`Right`/
`Up`/`Down` (including application-keypad `\eO…` forms, since this plugin emits
`smkx`), `Alt-Left`/`Alt-Right` and `Alt-f`/`Alt-b` for word motion, `^A`/`^E`,
`^F`/`^B`, `Alt-d`/`Alt-Backspace`/`^W` to kill words, `^K`/`^U`, `^Y`, `^T`/
`Alt-t`, `^_` undo, `^R`/`^S` history search, `^L` clear. Normal mode (`vicmd`)
is left as stock vi. Because the keys are bound additively, anything you bind
afterwards (fzf, a keybinds module, …) overrides these.

## Showing the mode in your prompt

The plugin core is prompt-agnostic: on every mode change it sets `VI_KEYMAP`,
runs any `vi_mode_before_redraw_functions` (see below), and issues
`zle reset-prompt; zle -R`. How the indicator reaches the screen depends on
which kind of prompt you use.

### Prompt-expansion prompts (oh-my-zsh themes, hand-rolled `$PROMPT`)

These embed `$(vi_mode_prompt_info)` in `$PROMPT`/`$RPROMPT`, which zsh
re-expands on every `reset-prompt`. **Nothing extra is needed** — the redraw
the plugin already does updates the indicator. If neither `$RPS1` nor `$RPROMPT`
is set when the plugin loads, it defaults `RPS1='$(vi_mode_prompt_info)'`. To
place it yourself:

```zsh
PROMPT="$PROMPT"'$(vi_mode_prompt_info)'
RPROMPT='$(vi_mode_prompt_info)'"$RPROMPT"
```

The single quotes matter: they defer evaluation so it's recomputed each redraw.

### Render-baked prompts (oh-my-posh, etc.)

These render once per `precmd` into a static string, so `reset-prompt` alone
redraws the *old* mode. oh-my-posh is the common case: its indicator comes from
an env var (e.g. `$VIMODE`) that the `oh-my-posh` binary reads at render time.

Append a function to `vi_mode_before_redraw_functions`. The plugin calls each
entry — inside the ZLE widget, right before it redraws — so you can refresh the
env var and let the prompt's **own** renderer rebuild the affected block:

```zsh
# oh-my-posh: VIMODE lives in the theme's rprompt block.
# _omp_get_prompt is oh-my-posh's own renderer (it uses it internally), so this
# anchors through omp rather than hand-building a prompt string.
function _vimode_omp_refresh() {
  set_poshcontext                   # exports VIMODE="$(vi_mode_prompt_info)"
  RPROMPT=$(_omp_get_prompt right)  # omp re-renders just the right block
}
vi_mode_before_redraw_functions+=(_vimode_omp_refresh)
```

Re-render only the block that carries the indicator (here `right`) — it runs on
every mode change, so avoid re-rendering an expensive left prompt (git status,
etc.). This works whether or not oh-my-posh streaming is enabled; streaming only
affects how the left/primary prompt is delivered.

## Cursor styles

```zsh
VI_MODE_SET_CURSOR=true
# defaults
VI_MODE_CURSOR_NORMAL=2   # solid block
VI_MODE_CURSOR_VISUAL=6   # solid line
VI_MODE_CURSOR_INSERT=6   # solid line
VI_MODE_CURSOR_OPPEND=2   # follows NORMAL (see below)
```

`VI_MODE_CURSOR_OPPEND` (the cursor while an operator like `d` waits for its
motion) defaults to the **normal-mode** shape, not omz's `0`. ZLE doesn't
reliably fire `zle-keymap-select` on the `viopp → vicmd` return, so a distinct
operator-pending shape tends to get stuck after e.g. `dw`; keeping it equal to
normal avoids that. Set it explicitly if you want a separate oppend cursor.

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
