# zsh-vim-mode
#
# A fork of oh-my-zsh's `vi-mode` plugin, focused on reliable prompt redraws on
# mode change, order-independence, and clean configuration.
#
# All configuration is via zstyle under the ':zsh-vim-mode:*' context — set
# these BEFORE sourcing the plugin:
#
#   # global
#   zstyle ':zsh-vim-mode:'  set-cursor      yes        # change cursor per mode (default: no)
#   zstyle ':zsh-vim-mode:'  redraw          always     # always | auto | never  (default: always)
#   zstyle ':zsh-vim-mode:'  insert-keymap   emacs      # emacs | viins          (default: viins)
#   zstyle ':zsh-vim-mode:'  clipboard       yes        # yank/paste to clipboard (default: yes)
#   zstyle ':zsh-vim-mode:'  redraw-hooks    _my_fn     # fns run before each mode-change redraw
#
#   # per mode (normal | insert | visual | visual-line | op)
#   zstyle ':zsh-vim-mode:normal'  indicator '[Normal]'
#   zstyle ':zsh-vim-mode:insert'  indicator ''         # blank
#   zstyle ':zsh-vim-mode:normal'  cursor    block      # block|line|underline|bar|blink-* | 0-6
#
# Public API: `vi_mode_prompt_info` (emits the current mode's indicator) and the
# `VI_KEYMAP` / `VI_VISUAL_LINE` state it reads.

# ----------------------------------------------------------------------------
# Defaults
# ----------------------------------------------------------------------------

typeset -gA _zsh_vim_mode_indicator_default=(
  normal      '[Normal]'
  insert      '[Ins]'
  visual      '[Visual]'
  visual-line '[V-Line]'
  op          '[Normal]'
)

# Per-mode default cursor (symbolic; mapped to DECSCUSR below).
typeset -gA _zsh_vim_mode_cursor_default=(
  normal block  insert line  visual line  visual-line line  op block
)

# Friendly cursor names -> DECSCUSR codes. See
# https://vt100.net/docs/vt510-rm/DECSCUSR
typeset -gA _zsh_vim_mode_cursor_code=(
  default 0  blink-block 1  block 2  blink-underline 3
  underline 4  blink-line 5  blink-bar 5  line 6  bar 6
)

typeset -g VI_KEYMAP=${VI_KEYMAP:=main}
typeset -g VI_VISUAL_LINE=${VI_VISUAL_LINE:=0}

# ----------------------------------------------------------------------------
# Mode resolution
# ----------------------------------------------------------------------------

# Resolve the symbolic mode name from the cached keymap state into $REPLY,
# avoiding a subshell.
_zsh_vim_mode_name() {
  case "${VI_KEYMAP:-main}" in
    vicmd)  REPLY=normal ;;
    viopp)  REPLY=op ;;
    visual) [[ "${VI_VISUAL_LINE:-0}" == 1 ]] && REPLY=visual-line || REPLY=visual ;;
    *)      REPLY=insert ;;
  esac
}

# ----------------------------------------------------------------------------
# Cursor shape
# ----------------------------------------------------------------------------

_zsh_vim_mode_set_cursor() {
  zstyle -t ':zsh-vim-mode:' set-cursor || return
  local REPLY; _zsh_vim_mode_name
  local shape
  zstyle -s ":zsh-vim-mode:$REPLY" cursor shape || shape=$_zsh_vim_mode_cursor_default[$REPLY]
  printf '\e[%d q' "${_zsh_vim_mode_cursor_code[$shape]:-$shape}"
}

# Cursor used while a command runs (between preexec and the next prompt).
_zsh_vim_mode_reset_cursor() {
  zstyle -t ':zsh-vim-mode:' set-cursor && printf '\e[0 q'
}

# ----------------------------------------------------------------------------
# Prompt redraw
# ----------------------------------------------------------------------------

_zsh_vim_mode_should_redraw() {
  local mode
  zstyle -s ':zsh-vim-mode:' redraw mode || mode=always
  case "$mode" in
    always) return 0 ;;
    auto)   [[ "${PROMPT} ${RPROMPT} ${PS1} ${RPS1}" == *'vi_mode_prompt_info'* ]] ;;
    *)      return 1 ;;
  esac
}

# Redraw the prompt immediately. Runs any registered redraw-hooks first (a seam
# for render-baked prompts like oh-my-posh — see README). A no-op outside ZLE.
_zsh_vim_mode_redraw() {
  [[ -n "${WIDGET:-}" ]] || return
  local -a hooks; local f
  zstyle -a ':zsh-vim-mode:' redraw-hooks hooks
  for f in $hooks; do (( ${+functions[$f]} )) && "$f"; done
  zle reset-prompt
  zle -R
}

# ----------------------------------------------------------------------------
# ZLE / shell hooks
#
# Only `keymap-select` is hooked as a zle widget (the mode-change event). The
# per-line housekeeping lives in precmd/preexec so we never tangle with the
# contested zle-line-init / zle-line-finish widgets (oh-my-posh, autosuggestions,
# fast-syntax-highlighting). This keeps the plugin order-independent.
# ----------------------------------------------------------------------------

_zsh_vim_mode_keymap_select() {
  typeset -g VI_KEYMAP=$KEYMAP
  _zsh_vim_mode_should_redraw && _zsh_vim_mode_redraw
  _zsh_vim_mode_set_cursor
}

# Re-assert the cursor on every redraw. vi command-mode operators (dw, x, p, …)
# DON'T change the keymap — you stay in vicmd — so keymap-select never fires and
# the cursor is never re-stamped after them. Anything that nudges the cursor in
# the meantime (a prompt redraw, terminal shell integration, …) then sticks.
# line-pre-redraw fires after every widget, so we restamp the current mode's
# cursor here. It's emitted unconditionally (not guarded on a remembered shape)
# precisely so an *external* change gets corrected — a repeated identical
# DECSCUSR is a no-op in the terminal.
_zsh_vim_mode_line_pre_redraw() {
  typeset -g VI_KEYMAP=$KEYMAP
  _zsh_vim_mode_set_cursor
}

# `visual-mode` / `visual-line-mode` don't emit a keymap-select event on their
# own; wrap them to track the charwise/linewise distinction (VI_VISUAL_LINE) and
# keep the cursor/prompt in sync. The flag is set before the real widget so a
# redraw triggered from here sees it.
_zsh_vim_mode_visual() {
  typeset -g VI_KEYMAP=visual VI_VISUAL_LINE=0
  zle .visual-mode
  _zsh_vim_mode_should_redraw && _zsh_vim_mode_redraw
  _zsh_vim_mode_set_cursor
}

_zsh_vim_mode_visual_line() {
  typeset -g VI_KEYMAP=visual VI_VISUAL_LINE=1
  zle .visual-line-mode
  _zsh_vim_mode_should_redraw && _zsh_vim_mode_redraw
  _zsh_vim_mode_set_cursor
}

# Each new command line starts in insert mode.
_zsh_vim_mode_precmd() {
  typeset -g VI_KEYMAP=main VI_VISUAL_LINE=0
  (( ! ${+terminfo[smkx]} )) || echoti smkx
  _zsh_vim_mode_set_cursor
}

# Before a command runs, return to a neutral keymap/cursor.
_zsh_vim_mode_preexec() {
  typeset -g VI_KEYMAP=main VI_VISUAL_LINE=0
  (( ! ${+terminfo[rmkx]} )) || echoti rmkx
  _zsh_vim_mode_reset_cursor
}

# ----------------------------------------------------------------------------
# Clipboard integration (wraps the vi yank/change/delete/put widgets)
# ----------------------------------------------------------------------------

_zsh_vim_mode_clipboard_wrap() {
  # NB: assumes we are the first wrapper and only wrap native widgets.
  local verb="$1"; shift
  local widget wrapped_name
  for widget in "$@"; do
    wrapped_name="_zsh_vim_mode_clip_${verb}_${widget}"
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

# ----------------------------------------------------------------------------
# Prompt mode indicator (public)
# ----------------------------------------------------------------------------

function vi_mode_prompt_info() {
  local REPLY; _zsh_vim_mode_name
  local ind
  zstyle -s ":zsh-vim-mode:$REPLY" indicator ind || ind=$_zsh_vim_mode_indicator_default[$REPLY]
  print -rn -- "$ind"
}

# ----------------------------------------------------------------------------
# Install (guarded so re-sourcing can't double-register / re-clobber bindings)
# ----------------------------------------------------------------------------

if (( ! ${+_zsh_vim_mode_installed} )); then
  typeset -g _zsh_vim_mode_installed=1

  # --- insert keymap ---------------------------------------------------------
  () {
    local ins; zstyle -s ':zsh-vim-mode:' insert-keymap ins || ins=viins
    if [[ $ins == emacs ]]; then
      # Insert mode IS the emacs keymap: full readline editing for free, and it
      # stays live/order-independent (no enumerating keys). ESC drops to vi
      # command mode and coexists with the ^[-prefixed meta keys via KEYTIMEOUT.
      bindkey -e
      bindkey -A emacs viins              # vi-insert/a/o/... return here, not sparse viins
      bindkey -M emacs '^[' vi-cmd-mode
    else
      # Conventional (sparse) vi insert keymap, plus the common readline keys
      # that bare viins drops. For full emacs editing use insert-keymap=emacs.
      bindkey -v
      local k
      for k in '^A:beginning-of-line'   '^E:end-of-line' \
               '^P:up-history'          '^N:down-history' \
               '^R:history-incremental-search-backward' \
               '^S:history-incremental-search-forward' \
               '^?:backward-delete-char' '^H:backward-delete-char' \
               '^W:backward-kill-word'; do
        bindkey -M viins "${k%%:*}" "${k#*:}"
      done
    fi
  }

  # --- vv to edit the command line in $EDITOR (vicmd) ------------------------
  autoload -Uz edit-command-line
  zle -N edit-command-line
  bindkey -M vicmd 'vv' edit-command-line

  # --- visual-mode wrappers --------------------------------------------------
  zle -N visual-mode      _zsh_vim_mode_visual
  zle -N visual-line-mode _zsh_vim_mode_visual_line

  # --- hooks -----------------------------------------------------------------
  autoload -Uz add-zsh-hook
  add-zsh-hook precmd  _zsh_vim_mode_precmd
  add-zsh-hook preexec _zsh_vim_mode_preexec

  (( ${+functions[add-zle-hook-widget]} )) || \
    autoload -Uz +X add-zle-hook-widget 2>/dev/null
  if (( ${+functions[add-zle-hook-widget]} )); then
    add-zle-hook-widget keymap-select   _zsh_vim_mode_keymap_select
    add-zle-hook-widget line-pre-redraw _zsh_vim_mode_line_pre_redraw
  else
    function zle-keymap-select()   { _zsh_vim_mode_keymap_select "$@" }
    function zle-line-pre-redraw() { _zsh_vim_mode_line_pre_redraw "$@" }
    zle -N zle-keymap-select
    zle -N zle-line-pre-redraw
  fi

  # --- clipboard -------------------------------------------------------------
  if zstyle -T ':zsh-vim-mode:' clipboard; then    # default yes
    _zsh_vim_mode_clipboard_wrap copy \
        vi-yank vi-yank-eol vi-yank-whole-line \
        vi-change vi-change-eol vi-change-whole-line \
        vi-kill-line vi-kill-eol vi-backward-kill-word \
        vi-delete vi-delete-char vi-backward-delete-char
    _zsh_vim_mode_clipboard_wrap paste \
        vi-put-{before,after} \
        put-replace-selection
  fi
  unfunction _zsh_vim_mode_clipboard_wrap

  # --- default right prompt, if no theme set one -----------------------------
  if [[ -z "$RPS1" && -z "$RPROMPT" ]]; then
    RPS1='$(vi_mode_prompt_info)'
  fi
fi
