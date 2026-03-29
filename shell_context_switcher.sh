CONFIG_DIR="$HOME/.config/shell-context-switcher"
CURRENT_CONTEXT_FILE="${CONFIG_DIR}/current_context"
if [[ ! -f "$CURRENT_CONTEXT_FILE" ]]; then
  mkdir -p "$CONFIG_DIR" 2>/dev/null
  touch "$CURRENT_CONTEXT_FILE" 2>/dev/null
fi
current_context=""
if [[ -f "$CURRENT_CONTEXT_FILE" ]]; then
  current_context="$(<"$CURRENT_CONTEXT_FILE")"
fi
EXTENSIONS_DIR="${CONFIG_DIR}/extensions"
STATE_DIR="${EXTENSIONS_DIR}/state"
PROFILES_DIR="${CONFIG_DIR}/profiles"

if [[ -z "${current_shell+x}" ]]; then
  if [ -n "$ZSH_VERSION" ]; then
    readonly current_shell="zsh"
  elif [ -n "$BASH_VERSION" ]; then
    readonly current_shell="bash"
  else
    echo "Unsupported shell"
    return 1
  fi
fi

configure() {
  local profile="$1"
  local action="$2"
  local profile_name="$3"
  local init="$4"
  local profile_dir="${PROFILES_DIR}/$profile"

  local extension_name
  local profile_config
  setopt local_options nullglob 2>/dev/null || shopt -s nullglob
  for extension_file in "$EXTENSIONS_DIR"/bundled/* "$EXTENSIONS_DIR"/custom/*; do
      [ -f "$extension_file" ] || continue
      [[ "$extension_file" == *.disabled ]] && continue

      extension_name="$(basename "$extension_file")"

      profile_config="$profile_dir/$extension_name"
      [ -f "$profile_config" ] || continue

      export SCS_EXTENSION_CONFIG="$profile_config"
      export SCS_STATE_DIR="$STATE_DIR"
      export SCS_PROFILE="$profile"
      source "$extension_file"

      case "$action" in
        set)
          "${extension_name}_on_up"
          ;;
        unset)
          "${extension_name}_on_down"
          ;;
        show)
          "${extension_name}_on_show"
      esac
  done
}

get_help() {
  local extension_name="$1"
  local extension_file

  if [[ -z "$extension_name" ]]; then
    echo "Shell Context Switcher (SCS)"
    echo
    echo "Usage: scs [option] [argument]"
    echo
    echo "Options:"
    echo "  (no option)                Show current profile and its configuration"
    echo "  -s, --switch <profile>     Switch to the specified profile"
    echo "  -r, --reload               Reload the current profile"
    echo "  -e, --ext <extension>      Run an extension command (see extension help)"
    echo "  -i, --installer            Launch the SCS installer (if installed)"
    echo "  -h, --help                 Show this help message"
    echo "  -h, --help <extension>     Show help for a specific extension"
    echo
    echo "Available extensions:"
    setopt local_options nullglob 2>/dev/null || shopt -s nullglob
    for extension_file in "$EXTENSIONS_DIR"/bundled/* "$EXTENSIONS_DIR"/custom/*; do
      [ -f "$extension_file" ] || continue
      [[ "$extension_file" == *.disabled ]] && continue
      echo "  $(basename "$extension_file")"
    done
    echo
    echo "Profiles are stored in: ${PROFILES_DIR}"
    return 0
  fi

  extension_file="${EXTENSIONS_DIR}/bundled/${extension_name}"
  if [[ ! -f "$extension_file" ]]; then
    extension_file="${EXTENSIONS_DIR}/custom/${extension_name}"
  fi
  if [[ ! -f "$extension_file" ]]; then
    echo "Extension '$extension_name' not found."
    return 1
  fi
  export SCS_STATE_DIR="$STATE_DIR"
  source "$extension_file"
  "${extension_name}_on_help"
}

get_context() {
  if [[ -z "$current_context" ]]; then
    echo "No profile has been set! Please switch to a new profile to retrieve profile settings."
    echo "You can do so via 'scs -s <profile>'"
    return 1
  fi
  local profile_name
  if ! profile_name="$(get_nicename "$current_context")"; then
    echo "Profile $current_context not configured"
    return 1
  fi
  echo "Current profile: $profile_name"
  echo "$profile_name configuration:"
  configure "$current_context" 'show' "$profile_name"
  return 0
}

get_nicename() {
  local profile="$1"
  local profile_dir="${PROFILES_DIR}/${profile}"
  if [ -d "$profile_dir" ]; then
    local profile_nicename_file="${profile_dir}/profile_nicename"
    if [ -f "${profile_nicename_file}" ]; then
      local profile_name="$(<"$profile_nicename_file")"
    else
      local profile_name="$profile"
    fi
  else
    return 1
  fi
  echo "$profile_name"
}

set_context() {
  local profile="$1"
  local profile_name
  local init="$2"
  if ! profile_name="$(get_nicename "$profile")"; then
    echo "Profile $profile not configured"
    return 1
  fi
  if [[ -n "$current_context" ]]; then
    if [[ -z "$init" ]]; then
      echo "Disabling profile: $profile_name"
      echo
      configure "$current_context" 'unset' "$profile_name"
    else
      configure "$current_context" 'unset' "$profile_name" 'init'
    fi
  fi
  if [[ -z "$init" ]]; then
    echo "Enabling profile: $profile_name"
    echo
    configure "$profile" 'set' "$profile_name"
    echo
  else
    configure "$profile" 'set' "$profile_name" 'init'
  fi
  echo "$profile" > "${CONFIG_DIR}/current_context"
  current_context="$profile"
  if [[ -z "$init" ]]; then
    echo "Profile $profile_name enabled!"
    echo "------------------"
    get_context
  fi
  return 0
}

reload() {
  local is_init="$1"
  if [[ -z "$current_context" ]]; then
    if [[ -z "$is_init" ]]; then
      echo "No profile has been set! Please switch to a new profile to retrieve profile settings."
      echo "You can do so via 'scs -s <profile>'"
      return 1
    fi
    return 1
  fi
  if [[ -z "$is_init" ]]; then
      echo "Reloading current context: $current_context"
    set_context "$current_context"
  else
    set_context "$current_context" >/dev/null
  fi
  return 0
}

run_extension_command() {
  local ext_name="$1"
  shift

  if [[ -z "$current_context" ]]; then
    echo "No profile set. Switch to a profile first via 'scs -s <profile>'"
    return 1
  fi

  if [[ -z "$ext_name" ]]; then
    echo "No extension specified."
    echo "Usage: scs -e <extension> [args...]"
    return 1
  fi

  local extension_file="${EXTENSIONS_DIR}/bundled/${ext_name}"
  if [[ ! -f "$extension_file" ]]; then
    extension_file="${EXTENSIONS_DIR}/custom/${ext_name}"
  fi
  if [[ ! -f "$extension_file" ]]; then
    echo "Extension '$ext_name' not found."
    return 1
  fi

  local profile_config="${PROFILES_DIR}/${current_context}/${ext_name}"
  if [[ ! -f "$profile_config" ]]; then
    echo "Extension '$ext_name' is not configured for the current profile."
    return 1
  fi

  export SCS_EXTENSION_CONFIG="$profile_config"
  export SCS_STATE_DIR="$STATE_DIR"
  export SCS_PROFILE="$current_context"
  source "$extension_file"

  if ! typeset -f "${ext_name}_on_command" > /dev/null 2>&1; then
    echo "Extension '$ext_name' does not support direct commands."
    return 1
  fi

  "${ext_name}_on_command" "$@"
}

if [[ "$#" -eq 0 ]]; then
  get_context
  return 0
fi

case "$1" in
  --init)
    reload "init"
    ;;
  -i|--installer)
    if [[ -f "${CONFIG_DIR}/installer.sh" ]]; then
      "$current_shell" "${CONFIG_DIR}/installer.sh"
    else
      echo "Installer not detected."
      echo "Please download installer.sh from the SCS repository and place it in ${CONFIG_DIR}/"
    fi
    ;;
  -h|--help)
    get_help "$2"
    ;;
  -s|--switch)
    if [[ -z "$2" ]]; then
        echo "No profile provided to switch to."
        return 1
    fi
    if [[ ! -d "${PROFILES_DIR}/$2" ]]; then
        echo "Chosen context does not exist!"
        return 1
    fi
    set_context "$2"
    ;;
  -e|--ext)
    run_extension_command "${@:2}"
    ;;
  -r|--reload)
    reload
    ;;
  *)
    echo "Invalid option: $1"
    echo "Run 'scs --help' for usage information."
    return 1
    ;;
esac
