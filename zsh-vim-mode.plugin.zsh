# zsh-vim-mode
#
# A fork of oh-my-zsh's `vi-mode` plugin, focused on making prompt redraws on
# mode changes reliable and well-behaved.
#
# Key differences from upstream omz vi-mode:
#   * Mode changes redraw the prompt by default (VI_MODE_RESET_PROMPT_ON_MODE_CHANGE=true).
#   * Order-independent and conflict-free with prompt/editing plugins. The only
#     zle widget we hook is `keymap-select` (the mode-change event), via
#     `add-zle-hook-widget`. The per-line housekeeping omz did in the
#     `zle-line-init` / `zle-line-finish` widgets is done in `precmd` / `preexec`
#     instead, so we never tangle with oh-my-posh / zsh-autosuggestions /
#     fast-syntax-highlighting on those contested widgets (see the long note by
#     the hook installation below).
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
# Operator-pending (e.g. the `d` of `dw`). Defaults to the normal-mode shape
# rather than omz's `0` (terminal default): ZLE does not reliably fire
# `zle-keymap-select` on the viopp -> vicmd return, so a distinct oppend shape
# tends to get "stuck" after an operator. Keeping it the same as normal means
# the cursor simply stays a block throughout. Override if you really want a
# distinct operator-pending cursor.
typeset -g VI_MODE_CURSOR_OPPEND=${VI_MODE_CURSOR_OPPEND:=$VI_MODE_CURSOR_NORMAL}

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

# Functions listed here are called (in order), inside the ZLE widget, right
# before each mode-change prompt redraw. Use this to refresh prompt state that
# is baked in at render time and therefore wouldn't update on a bare
# `reset-prompt`. The canonical case is oh-my-posh: its vi indicator comes from
# the $VIMODE env var, which is only recomputed in precmd, so a redraw alone
# shows a stale mode. An integration registers a function that recomputes the
# env var and re-renders the affected prompt. For example:
#
#   function _my_omp_vimode() {
#     set_poshcontext                     # export VIMODE="$(vi_mode_prompt_info)"
#     RPROMPT=$(_omp_get_prompt right)    # re-render the block that shows it
#   }
#   vi_mode_before_redraw_functions+=(_my_omp_vimode)
typeset -ga vi_mode_before_redraw_functions

# Redraw the command line / prompt immediately. Safe to call from any ZLE
# widget; a no-op outside ZLE.
function _vi-mode-reset-prompt() {
  # ${WIDGET} is only set while a ZLE widget is executing.
  [[ -n "${WIDGET:-}" ]] || return
  local _fn
  for _fn in "${vi_mode_before_redraw_functions[@]}"; do
    (( ${+functions[$_fn]} )) && "$_fn"
  done
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

# Per-line housekeeping runs in precmd/preexec rather than in the
# zle-line-init / zle-line-finish *widgets*, ON PURPOSE.
#
# zle-line-init is a contested widget: oh-my-posh decorates it (it runs
# `.recursive-edit` there), and zsh-autosuggestions / fast-syntax-highlighting
# wrap it too. add-zle-hook-widget "absorbs" any pre-existing widget into its
# hook list, so when these wrapping schemes meet on zle-line-init in the wrong
# combination the wrappers chain into each other and blow up with "maximum
# nested function level reached". The trigger is load order, which we refuse to
# depend on.
#
# precmd/preexec carry no such baggage: add-zsh-hook simply appends to an array,
# composes with every other consumer, and is completely order-independent. None
# of the work we do here (reset to insert mode, cursor shape, keypad mode) needs
# to live on the line-init widget — at precmd time the prompt is rendered fresh,
# so the indicator is already correct without a redraw.

# Runs before each prompt: every new command line starts in insert mode.
function vi-mode-precmd() {
  typeset -g VI_KEYMAP=main
  # Application keypad mode for line editing (was lib/key-bindings.zsh).
  (( ! ${+terminfo[smkx]} )) || echoti smkx
  _vi-mode-set-cursor-shape-for-keymap "${VI_KEYMAP}"
}

# Runs before a command executes: return to a neutral keymap/cursor.
function vi-mode-preexec() {
  typeset -g VI_KEYMAP=main
  (( ! ${+terminfo[rmkx]} )) || echoti rmkx
  _vi-mode-set-cursor-shape-for-keymap default
}

# Install the hooks. Guarded to run at most once per shell so that re-sourcing
# (e.g. reloading ~/.zshrc while testing) can't double-register anything.
if (( ! ${+_VI_MODE_HOOKS_INSTALLED} )); then
  typeset -g _VI_MODE_HOOKS_INSTALLED=1

  # precmd/preexec: always via add-zsh-hook (order-independent, never wrapped).
  autoload -Uz add-zsh-hook
  add-zsh-hook precmd  vi-mode-precmd
  add-zsh-hook preexec vi-mode-preexec

  # keymap-select is the only thing that genuinely needs a zle widget (it's the
  # mode-change event that drives the prompt redraw). Nothing else wraps it, so
  # add-zle-hook-widget composes here without the absorb hazard above.
  #
  # Don't use `autoload +X` blindly to probe for it: that errors if the function
  # is already defined (another plugin loaded it), which would wrongly send us to
  # the clobbering fallback.
  (( ${+functions[add-zle-hook-widget]} )) || \
    autoload -Uz +X add-zle-hook-widget 2>/dev/null

  if (( ${+functions[add-zle-hook-widget]} )); then
    add-zle-hook-widget keymap-select vi-mode-keymap-select
  else
    # Fallback for zsh < 5.3: define the widget directly.
    function zle-keymap-select() { vi-mode-keymap-select "$@" }
    zle -N zle-keymap-select
  fi
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
# Emacs-style insert mode (opt-in)
#
# Set VI_MODE_EMACS_INSERT=true to make insert mode (viins) behave like the
# standard emacs/readline "main" keymap: full editing keys while typing, and
# ESC still drops you into vi normal mode (vicmd). Exactly: editing works like
# main mode until you hit ESC.
#
# Bindings are ADDITIVE into viins (we never replace the keymap), so this stays
# order-independent and any bindings you set later — fzf, your keybinds module,
# etc. — still take precedence over these defaults. ESC-alone remains
# vi-cmd-mode; the ESC-prefixed Alt keys coexist with it via $KEYTIMEOUT.
# ----------------------------------------------------------------------------
if [[ "${VI_MODE_EMACS_INSERT:-}" == true ]]; then
  # Arrow keys. Both the normal (\e[X) and application-keypad (\eOX) forms are
  # bound because this plugin emits `smkx`, which switches the terminal into
  # application mode where arrows arrive as \eOA..\eOD.
  bindkey -M viins '\e[C'    forward-char           # Right
  bindkey -M viins '\eOC'    forward-char
  bindkey -M viins '\e[D'    backward-char          # Left
  bindkey -M viins '\eOD'    backward-char
  bindkey -M viins '\e[A'    up-line-or-history     # Up
  bindkey -M viins '\eOA'    up-line-or-history
  bindkey -M viins '\e[B'    down-line-or-history   # Down
  bindkey -M viins '\eOB'    down-line-or-history
  # Home / End (normal, application, and tilde forms)
  bindkey -M viins '\e[H'    beginning-of-line
  bindkey -M viins '\eOH'    beginning-of-line
  bindkey -M viins '\e[1~'   beginning-of-line
  bindkey -M viins '\e[F'    end-of-line
  bindkey -M viins '\eOF'    end-of-line
  bindkey -M viins '\e[4~'   end-of-line
  # Movement
  bindkey -M viins '^A'      beginning-of-line
  bindkey -M viins '^E'      end-of-line
  bindkey -M viins '^F'      forward-char
  bindkey -M viins '^B'      backward-char
  bindkey -M viins '\ef'     forward-word           # Alt-f
  bindkey -M viins '\eb'     backward-word          # Alt-b
  bindkey -M viins '\eC'     forward-word           # Alt-Right (Ghostty/ESC-letter form)
  bindkey -M viins '\eD'     backward-word          # Alt-Left
  bindkey -M viins '\e[1;5C' forward-word           # Ctrl-Right
  bindkey -M viins '\e[1;5D' backward-word          # Ctrl-Left
  bindkey -M viins '\e[1;3C' forward-word           # Alt-Right (xterm-style)
  bindkey -M viins '\e[1;3D' backward-word          # Alt-Left  (xterm-style)
  # Editing
  bindkey -M viins '^D'      delete-char
  bindkey -M viins '^H'      backward-delete-char
  bindkey -M viins '^?'      backward-delete-char
  bindkey -M viins '\ed'     kill-word              # Alt-d
  bindkey -M viins '\e^?'    backward-kill-word     # Alt-Backspace
  bindkey -M viins '^W'      backward-kill-word
  bindkey -M viins '^U'      backward-kill-line
  bindkey -M viins '^K'      kill-line
  bindkey -M viins '^Y'      yank
  bindkey -M viins '^T'      transpose-chars
  bindkey -M viins '\et'     transpose-words        # Alt-t
  bindkey -M viins '^_'      undo
  # History
  bindkey -M viins '^P'      up-line-or-history
  bindkey -M viins '^N'      down-line-or-history
  bindkey -M viins '^R'      history-incremental-search-backward
  bindkey -M viins '^S'      history-incremental-search-forward
  # Misc
  bindkey -M viins '^L'      clear-screen
fi

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
