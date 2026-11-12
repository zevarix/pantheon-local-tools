# shellcheck shell=bash
# Interactive Bash/zsh integration for Pantheon Local Tools.
# Registered automatically at shell startup by the PLT installer/first run.
#
# Both 'plt' and 'pantheon-local' will enter the newly created local directory
# after successful 'multidev' checkout or 'multidev create' operations.
# Other commands, dry runs, cancellation, and failures do not navigate.
#
# For source-only acceptance, set PANTHEON_LOCAL_SHELL_BIN to an absolute path
# to the candidate's bin/pantheon-local before sourcing this file.

plt() {
  local __plt_binary __plt_result __plt_exit __plt_directory
  __plt_binary=${PANTHEON_LOCAL_SHELL_BIN:-pantheon-local}

  if [ "${1:-}" != multidev ]; then
    command "$__plt_binary" "$@"
    return $?
  fi

  __plt_result=$(mktemp "${TMPDIR:-/tmp}/plt-chdir.XXXXXXXX") || {
    printf 'PLT: unable to allocate a temporary shell navigation result\n' >&2
    return 1
  }

  if PANTHEON_LOCAL_CHDIR_FILE="$__plt_result" command "$__plt_binary" "$@"; then
    __plt_exit=0
  else
    __plt_exit=$?
  fi

  if [ "$__plt_exit" -eq 0 ] && [ -s "$__plt_result" ]; then
    __plt_directory=''
    if IFS= read -r -d '' __plt_directory < "$__plt_result" && [ -d "$__plt_directory" ]; then
      if builtin cd -- "$__plt_directory"; then
        printf 'Working directory: %s\n' "$PWD"
      else
        printf 'PLT: checkout succeeded, but could not enter directory: %s\n' "$__plt_directory" >&2
      fi
    else
      printf 'PLT: checkout succeeded, but shell navigation directory was invalid; current directory unchanged\n' >&2
    fi
  fi

  rm -f -- "$__plt_result"
  return "$__plt_exit"
}

pantheon-local() {
  plt "$@"
}
