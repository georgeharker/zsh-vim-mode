# zsh-vim-mode

A fork of [oh-my-zsh's `vi-mode` plugin](https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/vi-mode),
focused on making **prompt redraws on mode changes reliable and well-behaved**.

The public function `vi_mode_prompt_info` and the vi key bindings are kept, but
**all configuration is via `zstyle`** under the `:zsh-vim-mode:*` context rather
than environment variables (see [Configuration](#configuration)).

## What's different from omz vi-mode

### 1. Mode changes redraw the prompt by default

Upstream only redrew the prompt if it could detect — via an exact substring
match for `'$(vi_mode_prompt_info)'` in `$PS1`/`$RPS1` — that you were showing
the mode in the prompt. That detection is brittle (themes that build the prompt
in `precmd`, store the indicator in a variable, or call the function any other
way all slip past it), so redraws frequently failed to happen.

Here, the `redraw` style defaults to `always`: every switch between insert /
normal / visual issues `zle reset-prompt; zle -R`, so the prompt indicator and
cursor always reflect the current mode.

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

This plugin sidesteps that entirely. The only zle widgets it hooks are
`keymap-select` — the actual mode-change event that drives the redraw — and
`line-pre-redraw` (which re-asserts the cursor shape after every widget), both
via `add-zle-hook-widget` (nothing contested wraps those). Everything omz did in
the `zle-line-init` / `zle-line-finish` *widgets* (reset to insert mode, cursor
shape, keypad mode) is instead done in `precmd` / `preexec`, registered with
`add-zsh-hook`. Those are plain hook arrays with no wrap/absorb semantics, so
the plugin composes with everything and **does not depend on load order** — it
works correctly whether it loads before or after oh-my-posh and the rest.

### 3. Smarter (optional) auto-detection

If you set `zstyle ':zsh-vim-mode:' redraw auto`, the plugin redraws only when
the prompt actually contains the mode indicator — matching the loose substring
`vi_mode_prompt_info` rather than the exact `$(...)` form, so it still fires
when a theme calls the function indirectly.

## Install

### Manual

```zsh
git clone https://github.com/georgeharker/zsh-vim-mode ~/.zsh/zsh-vim-mode
echo 'source ~/.zsh/zsh-vim-mode/zsh-vim-mode.plugin.zsh' >> ~/.zshrc
```

Load order does not matter — source it before or after oh-my-posh,
zsh-autosuggestions, fast-syntax-highlighting, etc.

### oh-my-zsh

Clone into your custom plugins dir and replace `vi-mode` in your plugin list:

```zsh
git clone https://github.com/georgeharker/zsh-vim-mode "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-vim-mode"
# plugins=(... zsh-vim-mode)   # remove the stock `vi-mode`
```

Loading both the stock `vi-mode` and this plugin is not recommended; this one
replaces it.

## Configuration

Everything is configured with `zstyle`, under the `:zsh-vim-mode:*` context.
Set these **before** sourcing the plugin (per-mode `indicator`/`cursor` and the
`set-cursor`/`redraw`/`redraw-hooks` styles are read live, so they can also be
changed later; `insert-keymap` and `clipboard` are read once at load).

### Global — context `:zsh-vim-mode:`

| style | values | default | meaning |
|-------|--------|---------|---------|
| `set-cursor` | bool | `no` | change the cursor shape per mode |
| `redraw` | `always` \| `auto` \| `never` | `always` | when to redraw the prompt on a mode change (`auto` = only if the prompt contains `vi_mode_prompt_info`) |
| `insert-keymap` | `viins` \| `emacs` | `viins` | which keymap insert mode uses (see below) |
| `clipboard` | bool | `yes` | copy/paste yank/put to the system clipboard |
| `redraw-hooks` | function names | — | functions run just before each mode-change redraw (see [render-baked prompts](#render-baked-prompts-oh-my-posh-etc)) |

```zsh
zstyle ':zsh-vim-mode:' set-cursor    yes
zstyle ':zsh-vim-mode:' redraw        always
zstyle ':zsh-vim-mode:' insert-keymap emacs
```

### Per mode — context `:zsh-vim-mode:<mode>`

`<mode>` is one of `normal`, `insert`, `visual`, `visual-line`, `op`
(operator-pending).

| style | meaning |
|-------|---------|
| `indicator` | string emitted by `vi_mode_prompt_info`; `''` shows nothing |
| `cursor` | `block`, `line`/`bar`, `underline`, any `blink-*`, or a raw DECSCUSR `0`–`6` |

```zsh
zstyle ':zsh-vim-mode:normal'      indicator '[Normal]'
zstyle ':zsh-vim-mode:insert'      indicator ''          # blank insert indicator
zstyle ':zsh-vim-mode:visual'      indicator '[Visual]'
zstyle ':zsh-vim-mode:visual-line' indicator '[V-Line]'
zstyle ':zsh-vim-mode:normal'      cursor    block
zstyle ':zsh-vim-mode:insert'      cursor    line
```

Indicator defaults are `[Normal]` `[Ins]` `[Visual]` `[V-Line]` (and `op`
follows normal). Indicator values go through prompt expansion in a zsh
`$PROMPT`/`$RPROMPT`, so `%F{…}`/`%B` work there; for oh-my-posh use plain text
or omp markup, since the value is rendered by the omp binary.

> Replace mode (`R`) currently reports as insert — it isn't a distinct keymap,
> so the prompt can't tell it apart without wrapping the `vi-replace` widget.

## Insert keymap

`insert-keymap` controls what insert mode actually *is*:

- `viins` (default) — the conventional, sparse vi insert keymap. The plugin
  re-adds the common readline keys it drops (`^A`/`^E`, `^P`/`^N`, `^R`/`^S`,
  `^W`, `^?`/`^H`).
- `emacs` — insert mode **is the emacs keymap**. You get the full readline
  editing set (arrows, `Alt`-word motion, `^A`/`^E`/`^K`/`^U`/`^Y`, history
  search, …) for free and *live*: anything bound to the emacs keymap by you or
  another plugin is active in insert mode, regardless of load order. `ESC` drops
  to vi command mode (it coexists with the `Alt`/meta keys via `$KEYTIMEOUT`).
  Normal/visual/operator modes are unchanged.

```zsh
zstyle ':zsh-vim-mode:' insert-keymap emacs
```

## Showing the mode in your prompt

The plugin core is prompt-agnostic: on every mode change it sets `VI_KEYMAP`,
runs the functions in the `redraw-hooks` style, and issues
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

First, add a segment to your oh-my-posh theme that renders the env var (a
`text` segment reading `{{ .Env.VIMODE }}` — put it in whichever block you like;
the right/rprompt block is common):

```toml
[[blocks.segments]]
  template   = '{{ .Env.VIMODE }}'
  foreground = 'p:white'
  background = 'transparent'
  type       = 'text'
  style      = 'plain'
```

Then keep it live: register a function in the `redraw-hooks` style. The plugin
calls each — inside the ZLE widget, right before it issues `reset-prompt` — so
you re-render omp there, then the plugin's `reset-prompt` displays the result:

```zsh
function set_poshcontext() { export VIMODE="$(vi_mode_prompt_info)" }
function _vimode_omp_render() {
  set_poshcontext                   # refresh $VIMODE for the new mode
  RPROMPT=$(_omp_get_prompt right)   # re-render the block that shows it
}
zstyle ':zsh-vim-mode:' redraw-hooks _vimode_omp_render
```

`_omp_get_prompt` is the least-invasive render omp exposes: it only *reads*
omp's cached state (status, execution-time, …) and prints, so it doesn't reset
those segments — it's the same call omp's tooltip feature uses. Render only the
block carrying the indicator (`right` here).

The simpler `zstyle ':zsh-vim-mode:' redraw-hooks _omp_precmd` also works — it
re-runs omp's whole precmd render (and refreshes `VIMODE` via `set_poshcontext`
itself) — but it re-captures `$?` and execution time, so the status and timing
segments reset on every mode change. Prefer `_omp_get_prompt`.

Either way it runs on every mode change, so keep the render cheap. Works whether
or not oh-my-posh streaming is enabled; streaming only affects the left prompt.

## Cursor styles

Set `set-cursor` and a per-mode `cursor` (defaults shown):

```zsh
zstyle ':zsh-vim-mode:'            set-cursor yes
zstyle ':zsh-vim-mode:normal'      cursor block       # solid block
zstyle ':zsh-vim-mode:insert'      cursor line        # solid line (bar)
zstyle ':zsh-vim-mode:visual'      cursor line
zstyle ':zsh-vim-mode:visual-line' cursor line
zstyle ':zsh-vim-mode:op'          cursor block       # operator-pending; follows normal
```

A `cursor` is a name — `block`, `line`/`bar`, `underline`, or any `blink-*` —
or a raw DECSCUSR number `0`–`6` (`0` default · `1` blink-block · `2` block ·
`3` blink-underline · `4` underline · `5` blink-line · `6` line). See
[DECSCUSR](https://vt100.net/docs/vt510-rm/DECSCUSR).

Operator-pending (`op`) defaults to the **normal** cursor rather than a distinct
shape: ZLE doesn't reliably fire `zle-keymap-select` on the `viopp → vicmd`
return, so a distinct oppend cursor tends to get stuck after e.g. `dw`. Set it
if you want one anyway.

### Terminals that manage the cursor themselves

Some terminals ship a shell-integration feature that **also** drives the cursor
shape from the keymap — e.g. Ghostty's `cursor` feature
(`shell-integration-features` includes `cursor`), and similar in others. That
makes two stampers fighting over one cursor: the terminal's reads the live
`$KEYMAP` directly, with no mode tracking, so it paints an insert bar on the
`main` keymap that ZLE transiently selects during a prompt redraw — exactly the
flicker-after-`dw` this plugin is built to avoid. Symptom: the cursor snaps back
to a bar in normal mode after operators (`dw`, `x`, `p`), then corrects on the
next keypress.

Pick **one** owner. To let this plugin own it (recommended — it has per-mode
shapes and tracks the real mode), disable the terminal's cursor feature:

- **Ghostty** — add `no-cursor` to `shell-integration-features` in `config`
  (e.g. `shell-integration-features = no-cursor,sudo,title`), then **fully
  reload Ghostty** — config changes don't reach already-running shells/windows.

Or do the reverse: let the terminal own it and set `zstyle ':zsh-vim-mode:'
set-cursor no`.

## Key bindings

`ESC` or `CTRL-[` enters normal mode. The plugin also binds:

- `vv` (normal mode) — edit the current command line in `$EDITOR`
- `ctrl-p` / `ctrl-n` — previous / next history
- `ctrl-r` / `ctrl-s` — incremental history search backward / forward
- `ctrl-a` / `ctrl-e` — beginning / end of line
- `ctrl-h` / `ctrl-w` / `ctrl-?` — delete char / word / char before cursor
- `v` (normal mode) — visual mode

Yank/delete/change copy to the system clipboard; `p`/`P` paste from it (unless
`zstyle ':zsh-vim-mode:' clipboard no`). This uses the `clipcopy`/`clippaste`
helpers — oh-my-zsh provides them; on a manual install define your own (or the
integration silently no-ops).

### Low `$KEYTIMEOUT`

A low `$KEYTIMEOUT` (< 15) makes multi-key bindings like `vv` hard to trigger.
Raise `$KEYTIMEOUT`, or rebind, e.g. `bindkey -M vicmd 'V' edit-command-line`.

## License

MIT, inheriting from oh-my-zsh. See [LICENSE](LICENSE).
