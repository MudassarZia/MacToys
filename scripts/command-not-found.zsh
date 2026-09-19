# Optional MacToys shell integration. Source this file from your ~/.zshrc.
# Does not replace an existing handler, run the failed command, or install packages.
if (( ! $+functions[command_not_found_handler] )); then
  function command_not_found_handler() {
    local mactoys_command="$1"
    print -u2 -r -- "zsh: command not found: $mactoys_command"
    if [[ "$mactoys_command" =~ '^[A-Za-z0-9][A-Za-z0-9_.+-]{0,80}$' ]]; then
      print -u2 -r -- "MacToys: try searching Homebrew with: brew search --formula -- ${(q)mactoys_command}"
    fi
    return 127
  }
fi
