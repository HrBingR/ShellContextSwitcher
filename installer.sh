#!/usr/bin/env bash
CONFIG_DIR="$HOME/.config/shell-context-switcher"
EXTENSIONS_DIR="${CONFIG_DIR}/extensions"
PROFILES_DIR="${CONFIG_DIR}/profiles"
INSTALL_DIR="$HOME/.local/bin"

case "$(basename "$SHELL")" in
  zsh)  readonly current_shell="zsh" ;;
  bash) readonly current_shell="bash" ;;
  *)    echo "Unsupported shell"; exit 1 ;;
esac

install() {
  echo "Welcome to the shell-context-switcher (SCS) installer."
  echo "Select Continue to install SCS."
  PS3="Please select an option: "
  select option in "Continue" "Reinstall/Update" "Uninstall" "Exit"; do
    case $option in
    Continue)
      if ! step_one; then
        echo "Exiting setup..."
        return 1
      fi
      return 0
      ;;
    Reinstall/Update)
      uninstall "true"
      if ! step_one; then
        echo "Exiting setup..."
        return 1
      fi
      return 0
      ;;
    Uninstall)
      uninstall
      return 0
      ;;
    Exit)
      echo "Exiting setup..."
      return 1
      ;;
    esac
  done < /dev/tty
}

cleanup() {
  local step="$1"
  rmdir "$EXTENSIONS_DIR"/bundled "$EXTENSIONS_DIR"/custom "$EXTENSIONS_DIR" "$PROFILES_DIR" "$INSTALL_DIR" 2>/dev/null
  if [[ "$step" == "current_context" ]]; then
    rm "${CONFIG_DIR}/current_context"
  fi
}

rc_teardown() {
  local shellrc="$1"
  local reinstall="$2"
  if grep -q "^alias scs=" "$shellrc"; then
    sed -i.bak '/^alias scs=/d' "$shellrc"
    if [[ -z "$reinstall" ]]; then
      echo "Removed scs alias from ${shellrc}."
    fi
  fi

  if grep -q 'source $HOME/.local/bin/shell_context_switcher.sh --init' "$shellrc"; then
    sed -i.bak '/source.*shell_context_switcher.sh --init/d' "$shellrc"
    if [[ -z "$reinstall" ]]; then
      echo "Removed source line from ${shellrc}."
    fi
  fi
}

uninstall() {
  local reinstall="$1"
  local shellrc
  if [[ -z "$reinstall" ]]; then
    echo "Are you sure you want to uninstall shell-context-switcher?"
    PS3="Please select an option: "
    select option in "Yes, uninstall" "No, cancel"; do
      case $option in
      "Yes, uninstall")
        break
        ;;
      "No, cancel")
        echo "Uninstall cancelled."
        return 0
        ;;
      esac
    done < /dev/tty
  fi
  if [[ "$current_shell" == "zsh" ]]; then
    shellrc="$HOME/.zshrc"
  else
    shellrc="$HOME/.bashrc"
  fi
  if [[ -z "$reinstall" ]]; then
    echo "Uninstalling SCS..."
    rc_teardown "$shellrc"
  else
    echo "Updating SCS..."
    rc_teardown "$shellrc" "true"

  fi

  if [[ -z "$reinstall" ]]; then
    rm -f "${CONFIG_DIR}/current_context"
  fi
  rm -f "${INSTALL_DIR}/shell_context_switcher.sh"
  if [[ -z "$reinstall" ]]; then
    rm -f "${CONFIG_DIR}/installer.sh"
  fi
  rm -rf "${EXTENSIONS_DIR}/bundled"
  rm -rf "${EXTENSIONS_DIR}/state"
  rmdir "${EXTENSIONS_DIR}" 2>/dev/null

  if [[ -d "${EXTENSIONS_DIR}/custom" ]] && [[ -n "$(ls -A "${EXTENSIONS_DIR}/custom")" ]] && [[ -z "$reinstall" ]]; then
    echo "Custom extensions directory has not been removed: ${EXTENSIONS_DIR}/custom"
  else
    rmdir "${EXTENSIONS_DIR}/custom" 2>/dev/null
    rmdir "${EXTENSIONS_DIR}" 2>/dev/null
  fi

  if [[ -d "${PROFILES_DIR}" ]] && [[ -n "$(ls -A "${PROFILES_DIR}")" ]] && [[ -z "$reinstall" ]]; then
    echo "Profiles directory has not been removed: ${PROFILES_DIR}"
  else
    rmdir "${PROFILES_DIR}" 2>/dev/null
  fi

  rmdir "${CONFIG_DIR}" 2>/dev/null

  if [[ -z "$reinstall" ]]; then
    echo "SCS has been uninstalled."
    echo "Please restart your shell or run 'source ${shellrc}' to apply the changes."
  fi
  return 0
}

step_one() {
  echo
  echo "Installing SCS..."
  local shellrc
  if [[ -f "${INSTALL_DIR}/shell_context_switcher.sh" ]]; then
    echo "SCS is already installed. Please select the Reinstall option if you wish to reinstall."
    return 1
  fi
  if ! mkdir -p "$INSTALL_DIR" "$PROFILES_DIR" "$EXTENSIONS_DIR"/{bundled,custom}; then
    echo "Unable to create required directories for installation."
    return 1
  fi
  if ! touch "${CONFIG_DIR}/current_context"; then
    echo "Unable to create required files"
    cleanup
    return 1
  fi
  if ! download_scs; then
    cleanup "current_context"
    return 1
  fi
  if [[ "$current_shell" == "zsh" ]]; then
    shellrc="$HOME/.zshrc"
  else
    shellrc="$HOME/.bashrc"
  fi
  rc_setup "$shellrc"
  echo "Downloading installer..."
  download_installer
  echo "Downloading extensions..."
  download_extension "git"
  download_extension "alias"
  download_extension "env"
  download_extension "k8s_context"
  echo "Installation successful!"

  echo "Please restart your shell or run 'source ${shellrc}' to apply the changes."
  return 0
}

rc_setup() {
  local shellrc="$1"
  local alias_set
  if ! grep -q "^alias scs=" "$shellrc" && ! command -v scs > /dev/null 2>&1; then
    echo 'alias scs="source $HOME/.local/bin/shell_context_switcher.sh"' >> "$shellrc"
    alias_set="true"
  else
    alias_set="false"
  fi
  local source_set
  if ! grep -qx "source $HOME/.local/bin/shell_context_switcher.sh --init" "$shellrc"; then
    if echo 'source $HOME/.local/bin/shell_context_switcher.sh --init' >> "$shellrc"; then
      source_set="true"
    else
      source_set="false"
    fi
  else
    source_set="false"
  fi
  if [[ "$alias_set" == "false" ]]; then
    echo "Unable to add 'scs' alias to ${shellrc}. You will need to add your own alias."
    echo "Ensure that when you do so, you source the script. Example:"
    echo 'alias <some_alias>="source $HOME/.local/bin/shell_context_switcher.sh"'
  else
    echo "Alias configured successfully."
  fi
  if [[ "$source_set" == "false" ]]; then
    echo "Unable to add required source line to ${shellrc}. You will need to add it manually for the script to function."
    echo "Add a new line to your ${shellrc} file, as follows:"
    echo 'source $HOME/.local/bin/shell_context_switcher.sh --init'
  else
    echo "Source configured successfully."
  fi
}

download_scs() {
  local url="https://raw.githubusercontent.com/HrBingR/ShellContextSwitcher/main/shell_context_switcher.sh"
  local dest="${INSTALL_DIR}/shell_context_switcher.sh"
  if ! curl -fsSL "$url" -o "$dest"; then
    echo "Failed to download shell_context_switcher.sh" >&2
    echo "Please follow the manual installation process"
    return 1
  fi
}

download_installer() {
  local url="https://raw.githubusercontent.com/HrBingR/ShellContextSwitcher/main/installer.sh"
  local dest="${CONFIG_DIR}/installer.sh"
  if ! curl -fsSL "$url" -o "$dest"; then
    echo "Failed to download installer.sh" >&2
    echo "Please download it manually from $url and place it in $dest"
    return 1
  fi
}

download_extension() {
  local name="$1"
  local url="https://raw.githubusercontent.com/HrBingR/ShellContextSwitcher/main/extensions/bundled/$name"
  local dest="${EXTENSIONS_DIR}/bundled/$name"
  if ! curl -fsSL "$url" -o "$dest"; then
    echo "Failed to download extension: $name" >&2
    echo "Please download the extension manually from $url and place it in $dest"
    return 1
  fi
}

install