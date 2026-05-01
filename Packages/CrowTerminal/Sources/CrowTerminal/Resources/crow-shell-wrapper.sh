#!/usr/bin/env bash
# crow-shell-wrapper — installs prompt-ready markers, then exec's the user's $SHELL.
#
# Bundled with Crow.app, copied to a temp path at terminal create time. The
# Crow app sets CROW_SENTINEL in the env (per-terminal) before exec'ing this
# script. Each prompt firing touches that file, which the Swift readiness
# detector polls.
#
# This wrapper is intentionally minimal:
#   1. Source the user's normal shell startup (zsh: .zshrc; bash: .bashrc) so
#      aliases / oh-my-zsh / asdf / nvm / starship keep working.
#   2. Install a precmd (zsh) or PROMPT_COMMAND (bash) hook that:
#        - emits OSC 133;A (FinalTerm prompt-start marker)
#        - emits a custom OSC 9;crow-ready marker (Crow-specific)
#        - touches $CROW_SENTINEL so Swift can poll without parsing output
#      When running under tmux, OSCs are wrapped in the DCS-tmux passthrough
#      envelope (\ePtmux;\e<seq>\e\\) so they survive tmux's emulator. The
#      bundled tmux.conf sets `allow-passthrough on` to make this work.
#   3. Preserve any pre-existing precmd / PROMPT_COMMAND.
#   4. Hand off via `exec "$SHELL" -i` so the shell sits at the same process
#      depth it would in any other terminal — no extra layer.

# CROW_SENTINEL must be set by the caller (Crow app or tmux new-window -e).
if [ -z "${CROW_SENTINEL:-}" ]; then
  echo "crow-shell-wrapper: CROW_SENTINEL env var is required" >&2
  exit 64
fi
export CROW_SENTINEL

if [ -z "${SHELL:-}" ]; then SHELL=/bin/zsh; fi

case "$SHELL" in
  *zsh)
    # zsh: we can't directly modify the user's .zshrc — instead, point ZDOTDIR
    # at a temp dir whose .zshrc sources the user's real config, then appends
    # our hook via add-zsh-hook (which composes with any existing precmd).
    ZTMP="$(mktemp -d -t crowzdotdir)"
    cat > "$ZTMP/.zshrc" <<'ZRC'
# Source the user's real config from their original ZDOTDIR (or $HOME).
if [ -n "${CROW_USER_ZDOTDIR:-}" ]; then
  ZDOTDIR="$CROW_USER_ZDOTDIR"
else
  ZDOTDIR="$HOME"
fi
[ -f "$ZDOTDIR/.zshrc" ] && source "$ZDOTDIR/.zshrc"

_crow_precmd() {
  if [ -n "${TMUX:-}" ]; then
    printf '\033Ptmux;\033\033]133;A\007\033\\'
    printf '\033Ptmux;\033\033]9;crow-ready\007\033\\'
  else
    printf '\033]133;A\007'
    printf '\033]9;crow-ready\007'
  fi
  : > "$CROW_SENTINEL" 2>/dev/null || true
}
autoload -Uz add-zsh-hook 2>/dev/null && add-zsh-hook precmd _crow_precmd
ZRC
    CROW_USER_ZDOTDIR="${ZDOTDIR:-$HOME}" ZDOTDIR="$ZTMP" exec "$SHELL" -i
    ;;
  *bash)
    BTMP="$(mktemp -t crowbashrc.XXXXXX)"
    cat > "$BTMP" <<'BRC'
[ -f "$HOME/.bashrc" ] && source "$HOME/.bashrc"
_crow_precmd() {
  if [ -n "${TMUX:-}" ]; then
    printf '\033Ptmux;\033\033]133;A\007\033\\'
    printf '\033Ptmux;\033\033]9;crow-ready\007\033\\'
  else
    printf '\033]133;A\007'
    printf '\033]9;crow-ready\007'
  fi
  : > "$CROW_SENTINEL" 2>/dev/null || true
}
# Preserve any existing PROMPT_COMMAND.
if [ -n "${PROMPT_COMMAND:-}" ]; then
  PROMPT_COMMAND="_crow_precmd; $PROMPT_COMMAND"
else
  PROMPT_COMMAND="_crow_precmd"
fi
BRC
    exec "$SHELL" --rcfile "$BTMP" -i
    ;;
  *)
    # fish / unknown: best-effort. Emit markers once at startup; no per-prompt
    # hook. Production work would extend this with shell-specific paths.
    if [ -n "${TMUX:-}" ]; then
      printf '\033Ptmux;\033\033]133;A\007\033\\\033Ptmux;\033\033]9;crow-ready\007\033\\'
    else
      printf '\033]133;A\007\033]9;crow-ready\007'
    fi
    : > "$CROW_SENTINEL" 2>/dev/null || true
    exec "$SHELL" -i
    ;;
esac
