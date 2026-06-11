#!/usr/bin/env zsh
# Regression test for the cursor shape stamped by the line-pre-redraw hook.
#
# The bug this guards: _zsh_vim_mode_line_pre_redraw used to do
# `VI_KEYMAP=$KEYMAP` before stamping. During a prompt redraw zsh transiently
# selects the `main` keymap, so $KEYMAP reads `main` even while you're in command
# mode — which painted an insert bar after every `dw`. The hook must stamp from
# the *tracked* VI_KEYMAP (set by keymap-select), never the live $KEYMAP.
#
# Run:  zsh test/cursor.zsh
emulate -L zsh

# Locate the plugin relative to this test file.
local here=${0:A:h}
local plugin=${here:h}/zsh-vim-mode.plugin.zsh
[[ -r $plugin ]] || { print -u2 "cannot read plugin at $plugin"; exit 2 }

zstyle ':zsh-vim-mode:' set-cursor yes
# Source for the function definitions only; the install block's bindkey/zle -N
# are irrelevant here (and emit harmless keypad/cursor resets) — swallow them.
source $plugin 2>/dev/null  # shuck: ignore=C002

# DECSCUSR codes used below: block=2, line/bar=6, underline=4.
typeset -i fails=0
check() {
  local vi=$1 km=$2 want=$3 desc=$4
  # Read by the sourced _zsh_vim_mode_* functions (globals), not locally.
  VI_KEYMAP=$vi KEYMAP=$km VI_VISUAL_LINE=${5:-0}  # shuck: ignore=C001
  local got=${"$(_zsh_vim_mode_line_pre_redraw)"//$'\e'/^[}
  if [[ $got == "$want" ]]; then
    print "  ok    $desc  [$got]"
  else
    print "  FAIL  $desc  got=[$got] want=[$want]"; (( fails++ ))
  fi
}

print "line-pre-redraw stamps the tracked VI_KEYMAP, not the live \$KEYMAP:"
# The regression: normal mode while a redraw flips live $KEYMAP to main.
check vicmd  main  '^[[2 q' 'normal,  KEYMAP flickers to main after dw -> block'
check vicmd  vicmd '^[[2 q' 'normal,  KEYMAP settled                   -> block'
check main   main  '^[[6 q' 'insert                                    -> bar'
check viopp  vicmd '^[[2 q' 'operator-pending (follows normal)         -> block'
check visual main  '^[[6 q' 'visual,  KEYMAP flickers to main          -> bar' 0
check visual main  '^[[6 q' 'v-line,  KEYMAP flickers to main          -> bar' 1

print ""
if (( fails )); then
  print "FAILED: $fails"; exit 1
else
  print "ok: all passed"
fi
