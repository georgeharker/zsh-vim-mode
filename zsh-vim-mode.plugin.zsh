# zsh-vim-mode
#
# A fork of oh-my-zsh's `vi-mode` plugin, focused on making prompt redraws on
# mode changes reliable and well-behaved.
#
# Key differences from upstream omz vi-mode:
#   * Mode changes redraw the prompt by default (VI_MODE_RESET_PROMPT_ON_MODE_CHANGE=true).
#   * ZLE hooks are installed via `add-zle-hook-widget` so this plugin composes
#     with other plugins (zsh-autosuggestions, zsh-syntax-highlighting, p10k, ...)
#     instead of clobbering their `zle-keymap-select` / `zle-line-init` /
#     `zle-line-finish` widgets.
#   * Prompt auto-detection (the `auto` mode) matches the loose substring
#     `vi_mode_prompt_info`, so it still fires when a theme calls the function
#     without the exact `$(vi_mode_prompt_info)` wrapper omz looked for.
#
# All public variable and function names from omz vi-mode are preserved, so this
# is a drop-in replacement.

# ----------------------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------------------

# Control whether to redraw the prompt on each mode change.
#
# Resetting the prompt on every mode change re-expands $PROMPT/$RPROMPT. This is
# cheap for prompts that compute expensive bits (git status, etc.) in `precmd`
# and store them in a variable, because `reset-prompt` does NOT re-run `precmd`.
# It can be costly only if you embed `$(slow-command)` substitutions directly in
# $PROMPT.
#
# Accepted values:
#   true   - always redraw on mode change (default)
#   auto   - redraw only if the prompt actually displays the vi-mode indicator
#   false  - never redraw (or any other value)
typeset -g VI_MODE_RESET_PROMPT_ON_MODE_CHANGE=${VI_MODE_RESET_PROMPT_ON_MODE_CHANGE:=true}

# Control whether to change the cursor style on mode change.
#
# Set to "true" to change the cursor on each mode change.
# Unset or set to any other value to do the opposite.
typeset -g VI_MODE_SET_CURSOR

# Control how the cursor appears in the various vim modes. This only applies
# if $VI_MODE_SET_CURSOR=true.
#
# See https://vt100.net/docs/vt510-rm/DECSCUSR for cursor styles
typeset -g VI_MODE_CURSOR_NORMAL=${VI_MODE_CURSOR_NORMAL:=2}
typeset -g VI_MODE_CURSOR_VISUAL=${VI_MODE_CURSOR_VISUAL:=6}
typeset -g VI_MODE_CURSOR_INSERT=${VI_MODE_CURSOR_INSERT:=6}
typeset -g VI_MODE_CURSOR_OPPEND=${VI_MODE_CURSOR_OPPEND:=0}

typeset -g VI_KEYMAP=${VI_KEYMAP:=main}

# ----------------------------------------------------------------------------
# Cursor shape
# ----------------------------------------------------------------------------

function _vi-mode-set-cursor-shape-for-keymap() {
  [[ "$VI_MODE_SET_CURSOR" = true ]] || return

  # https://vt100.net/docs/vt510-rm/DECSCUSR
  local _shape=0
  case "${1:-${VI_KEYMAP:-main}}" in
    main)    _shape=$VI_MODE_CURSOR_INSERT ;; # vi insert: line
    viins)   _shape=$VI_MODE_CURSOR_INSERT ;; # vi insert: line
    isearch) _shape=$VI_MODE_CURSOR_INSERT ;; # inc search: line
    command) _shape=$VI_MODE_CURSOR_INSERT ;; # read a command name
    vicmd)   _shape=$VI_MODE_CURSOR_NORMAL ;; # vi cmd: block
    visual)  _shape=$VI_MODE_CURSOR_VISUAL ;; # vi visual mode: block
    viopp)   _shape=$VI_MODE_CURSOR_OPPEND ;; # vi operation pending: blinking block
    *)       _shape=0 ;;
  esac
  printf $'\e[%d q' "${_shape}"
}

# ----------------------------------------------------------------------------
# Prompt redraw
# ----------------------------------------------------------------------------

# Decide whether a mode change should redraw the prompt.
function _vi-mode-should-reset-prompt() {
  case "${VI_MODE_RESET_PROMPT_ON_MODE_CHANGE:-true}" in
    true)
      return 0
      ;;
    auto)
      # Redraw only if the prompt actually shows the mode indicator. Match the
      # loose substring `vi_mode_prompt_info` rather than the exact
      # `$(vi_mode_prompt_info)` omz required, so it works regardless of how the
      # function is invoked. (PROMPT/RPROMPT are aliases of PS1/RPS1; listing all
      # four is just belt-and-suspenders.)
      [[ "${PROMPT} ${RPROMPT} ${PS1} ${RPS1}" == *'vi_mode_prompt_info'* ]]
      return $?
      ;;
    *)
      return 1
      ;;
  esac
}

# Redraw the command line / prompt immediately. Safe to call from any ZLE
# widget; a no-op outside ZLE.
function _vi-mode-reset-prompt() {
  # ${WIDGET} is only set while a ZLE widget is executing.
  [[ -n "${WIDGET:-}" ]] || return
  zle reset-prompt
  zle -R
}

# ----------------------------------------------------------------------------
# ZLE hook widgets
#
# Installed via `add-zle-hook-widget` (falling back to raw `zle -N` on
# zsh < 5.3) so we cooperate with other plugins instead of overwriting their
# widgets.
# ----------------------------------------------------------------------------

# Fires whenever the active keymap changes, i.e. on every mode switch.
function vi-mode-keymap-select() {
  # Update the keymap variable used by the prompt.
  typeset -g VI_KEYMAP=$KEYMAP

  if _vi-mode-should-reset-prompt; then
    _vi-mode-reset-prompt
  fi
  _vi-mode-set-cursor-shape-for-keymap "${VI_KEYMAP}"
}

# `visual-mode` does not emit a `zle-keymap-select` event on its own, so wrap it
# to keep VI_KEYMAP, the cursor, and the prompt in sync.
function _visual-mode {
  typeset -g VI_KEYMAP=visual
  zle .visual-mode
  if _vi-mode-should-reset-prompt; then
    _vi-mode-reset-prompt
  fi
  _vi-mode-set-cursor-shape-for-keymap "$VI_KEYMAP"
}
zle -N visual-mode _visual-mode

# Each new command line starts in insert mode. Redraw if we are arriving from a
# different mode so the indicator/cursor reflect the reset.
function vi-mode-line-init() {
  local prev_vi_keymap="${VI_KEYMAP:-}"
  typeset -g VI_KEYMAP=main

  [[ "$prev_vi_keymap" != 'main' ]] && _vi-mode-should-reset-prompt && _vi-mode-reset-prompt

  # These `echoti` statements were originally set in lib/key-bindings.zsh.
  (( ! ${+terminfo[smkx]} )) || echoti smkx
  _vi-mode-set-cursor-shape-for-keymap "${VI_KEYMAP}"
}

# When a line is accepted, return to a neutral mode/cursor.
function vi-mode-line-finish() {
  typeset -g VI_KEYMAP=main
  (( ! ${+terminfo[rmkx]} )) || echoti rmkx
  _vi-mode-set-cursor-shape-for-keymap default
}

# Install the hooks. Prefer add-zle-hook-widget for composability.
# `autoload -Uz +X` forces the function body to load now and fails if the
# function file isn't in $fpath (zsh < 5.3), letting us fall back cleanly.
if autoload -Uz +X add-zle-hook-widget 2>/dev/null; then
  add-zle-hook-widget keymap-select vi-mode-keymap-select
  add-zle-hook-widget line-init     vi-mode-line-init
  add-zle-hook-widget line-finish   vi-mode-line-finish
else
  # Fallback for zsh < 5.3: define the widgets directly. This clobbers any
  # existing widgets of the same name, matching omz's original behavior.
  function zle-keymap-select() { vi-mode-keymap-select "$@" }
  function zle-line-init()      { vi-mode-line-init "$@" }
  function zle-line-finish()    { vi-mode-line-finish "$@" }
  zle -N zle-keymap-select
  zle -N zle-line-init
  zle -N zle-line-finish
fi

# ----------------------------------------------------------------------------
# Key bindings
# ----------------------------------------------------------------------------

bindkey -v

# allow vv to edit the command line (standard behaviour)
autoload -Uz edit-command-line
zle -N edit-command-line
bindkey -M vicmd 'vv' edit-command-line

# allow ctrl-p, ctrl-n for navigate history (standard behaviour)
bindkey '^P' up-history
bindkey '^N' down-history

# allow ctrl-h, ctrl-w, ctrl-? for char and word deletion (standard behaviour)
bindkey '^?' backward-delete-char
bindkey '^h' backward-delete-char
bindkey '^w' backward-kill-word

# allow ctrl-r and ctrl-s to search the history
bindkey '^r' history-incremental-search-backward
bindkey '^s' history-incremental-search-forward

# allow ctrl-a and ctrl-e to move to beginning/end of line
bindkey '^a' beginning-of-line
bindkey '^e' end-of-line

# ----------------------------------------------------------------------------
# Clipboard integration
# ----------------------------------------------------------------------------

function wrap_clipboard_widgets() {
  # NB: Assume we are the first wrapper and that we only wrap native widgets
  # See zsh-autosuggestions.zsh for a more generic and more robust wrapper
  local verb="$1"
  shift

  local widget
  local wrapped_name
  for widget in "$@"; do
    wrapped_name="_zsh-vi-${verb}-${widget}"
    if [ "${verb}" = copy ]; then
      eval "
        function ${wrapped_name}() {
          zle .${widget}
          printf %s \"\${CUTBUFFER}\" | clipcopy 2>/dev/null || true
        }
      "
    else
      eval "
        function ${wrapped_name}() {
          CUTBUFFER=\"\$(clippaste 2>/dev/null || echo \$CUTBUFFER)\"
          zle .${widget}
        }
      "
    fi
    zle -N "${widget}" "${wrapped_name}"
  done
}

if [[ -z "${VI_MODE_DISABLE_CLIPBOARD:-}" ]]; then
  wrap_clipboard_widgets copy \
      vi-yank vi-yank-eol vi-yank-whole-line \
      vi-change vi-change-eol vi-change-whole-line \
      vi-kill-line vi-kill-eol vi-backward-kill-word \
      vi-delete vi-delete-char vi-backward-delete-char

  wrap_clipboard_widgets paste \
      vi-put-{before,after} \
      put-replace-selection

  unfunction wrap_clipboard_widgets
fi

# ----------------------------------------------------------------------------
# Prompt mode indicator
# ----------------------------------------------------------------------------

# if mode indicator wasn't setup by theme, define default, we'll leave INSERT_MODE_INDICATOR empty by default
typeset -g MODE_INDICATOR=${MODE_INDICATOR:='%B%F{red}<%b<<%f'}

function vi_mode_prompt_info() {
  echo "${${VI_KEYMAP/vicmd/$MODE_INDICATOR}/(main|viins)/$INSERT_MODE_INDICATOR}"
}

# define right prompt, if it wasn't defined by a theme
if [[ -z "$RPS1" && -z "$RPROMPT" ]]; then
  RPS1='$(vi_mode_prompt_info)'
fi
