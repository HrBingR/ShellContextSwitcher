# Shell Context Switcher (SCS)

A shell tool for quickly switching between named profiles that configure your shell environment — aliases, environment variables, Kubernetes contexts, git identities, and more — with a single command.

## Why

If you work across multiple projects, clients, or clusters, you likely find yourself juggling different sets of environment variables, shell aliases, git configs, and Kubernetes contexts. SCS lets you define named profiles that bundle all of these together, then swap between them instantly.

## Features

- **Profile-based** — group related configuration (env vars, aliases, k8s context, git identity) into a single switchable profile
- **Extension system** — bundled extensions handle common use cases; drop in your own for anything else
- **Clean transitions** — switching profiles tears down the previous profile's configuration before applying the new one
- **Shell startup reload** — automatically reloads your last active profile when a new shell starts
- **Bash and Zsh support**

## Compatibility

SCS is compatible with **Bash** and **Zsh** on **Linux** and **macOS**.

## Installation

### Automated

```sh
curl -fsSL https://raw.githubusercontent.com/HrBingR/ShellContextSwitcher/main/installer.sh | bash
```

Replace `bash` with `zsh` if that is your shell. After installation, restart your shell or run `source ~/.bashrc` (or `~/.zshrc`).

To reinstall or uninstall after an automated install, run `scs -i` (or `scs --installer`).

### Manual

1. Create the following directories:
   - `~/.local/bin/`
   - `~/.config/shell-context-switcher/profiles/`
   - `~/.config/shell-context-switcher/extensions/bundled/`
   - `~/.config/shell-context-switcher/extensions/custom/`
2. Create an empty file at `~/.config/shell-context-switcher/current_context`
3. Download `shell_context_switcher.sh` and save it to `~/.local/bin/`
4. Download the extensions from `extensions/bundled/` in the repository and save them to `~/.config/shell-context-switcher/extensions/bundled/`
5. Add the following lines to your `~/.bashrc` or `~/.zshrc`:
   ```sh
   alias scs="source $HOME/.local/bin/shell_context_switcher.sh"
   source $HOME/.local/bin/shell_context_switcher.sh --init
   ```
6. Restart your shell or source your rc file

## Usage

```sh
scs                              # Show current profile and its configuration
scs -s, --switch <profile>       # Switch to a profile
scs -r, --reload                 # Reload the current profile
scs -e, --ext <extension> [args] # Run an extension command
scs -i, --installer              # Launch the SCS installer (if installed)
scs -h, --help                   # Show general usage and list extensions
scs -h, --help <extension>       # Show help for a specific extension
```

## Directory Structure

```
~/.config/shell-context-switcher/
├── current_context          # Stores the name of the active profile
├── profiles/
│   └── <profile>/           # One directory per profile
│       ├── profile_nicename # Optional display name for the profile
│       ├── alias            # Config file for the alias extension
│       ├── env              # Config file for the env extension
│       ├── git              # Config file for the git extension
│       └── k8s_context      # Config file for the k8s_context extension
└── extensions/
    ├── bundled/             # Ships with SCS
    │   ├── alias
    │   ├── env
    │   ├── git
    │   └── k8s_context
    ├── custom/              # User-created extensions
    └── state/               # Runtime state used by extensions (e.g. git)
```

## Creating a Profile

1. Create a directory under `profiles/` with a short name (this is the ID you pass to `scs -s`):

   ```sh
   mkdir -p ~/.config/shell-context-switcher/profiles/work
   ```

2. Optionally, give it a human-readable display name:

   ```sh
   echo "Work (Acme Corp)" > ~/.config/shell-context-switcher/profiles/work/profile_nicename
   ```

3. Add configuration files for whichever extensions you want the profile to use. A profile only needs files for the extensions it cares about — missing files are silently skipped.

## Bundled Extensions

### alias

Sets and unsets shell aliases when switching profiles.

**Config file:** `profiles/<profile>/alias`

```
k='kubectl'
tf='terraform'
ls='ls -la'
```

Each line is a standard alias assignment (without the `alias` keyword).

### env

Exports and unsets environment variables when switching profiles.

**Config file:** `profiles/<profile>/env`

```
AWS_PROFILE=my-profile
VAULT_ADDR=https://vault.example.com:8200
VAULT_TOKEN=<~/tokens/my_token
```

**Do not** wrap values in quotes. Values are read literally, which means special characters like `$`, `@`, and spaces are preserved as-is without shell expansion. Quoting values will embed the literal quote characters into the variable.

To read a value from a file, prefix the path with `<`. Tilde (`~`) is expanded to the user's home directory. If the file is not found, a warning is printed and the variable is skipped.

### k8s_context

Switches the active `kubectl` context when a profile is activated. Supports multiple contexts per profile.

**Config file:** `profiles/<profile>/k8s_context`

Single context:

```
my-cluster-context
```

Multiple contexts (unnamed — use kubeconfig names directly):

```
my-dev-cluster
my-staging-cluster
my-prod-cluster
```

Multiple contexts (named — use friendly aliases):

```
default=my-dev-cluster
dev=my-dev-cluster
staging=my-staging-cluster
prod=my-prod-cluster
```

In named format, the `default` key is loaded on profile switch. In unnamed format, the first line is the default. The selected context persists across profile reloads.

To switch between contexts within the current profile:

```sh
scs -e k8s_context           # List available contexts
scs -e k8s_context prod      # Switch to a context (by key or name)
```

Context names must match existing entries in your kubeconfig. List them with `kubectl config get-contexts`.

### git

Switches the global git `user.name` and `user.email`. When switching away, SCS restores your previous git identity. If an external change to your git config is detected, you are prompted to resolve the conflict.

**Config file:** `profiles/<profile>/git`

```
name=Jane Smith
email=jane@example.com
```

## Writing Custom Extensions

Create a file in `~/.config/shell-context-switcher/extensions/custom/` named after your extension (e.g. `my_ext`). The file must define the following functions:

```sh
# Called when a profile containing this extension is activated
my_ext_on_up() {
  local config="$SCS_EXTENSION_CONFIG"   # Path to profiles/<profile>/my_ext
  # Apply configuration...
}

# Called when a profile containing this extension is deactivated
my_ext_on_down() {
  local config="$SCS_EXTENSION_CONFIG"
  # Revert configuration...
}

# Called when showing the current profile's status
my_ext_on_show() {
  local config="$SCS_EXTENSION_CONFIG"
  # Print current state...
}

# Called by `scs -h my_ext`
my_ext_on_help() {
  echo "Description and usage for my_ext."
}

# Optional: called by `scs -e my_ext [args...]`
# Only needed if your extension supports direct commands (e.g. switching between sub-configurations).
my_ext_on_command() {
  # $@ contains any arguments passed after the extension name
  # Handle listing, switching, etc.
}
```

The function names **must** be prefixed with the filename of the extension. All functions except `_on_command` are required. `_on_command` is optional and enables the `scs -e` interface for extensions that support sub-configurations.

SCS provides the following environment variables to extensions:

| Variable | Description |
|---|---|
| `SCS_EXTENSION_CONFIG` | Absolute path to the profile's config file for this extension |
| `SCS_STATE_DIR` | Directory for persisting state across profile switches (e.g. `extensions/state/`) |
| `SCS_PROFILE` | The current profile identifier |

To disable an extension without removing it, append `.disabled` to its filename.

## Uninstalling

If you installed via the automated method, run `scs -i` and select "Uninstall".

If you installed manually, reverse the manual installation steps: remove the alias and source lines from your rc file, then delete the `~/.config/shell-context-switcher/` directory and `~/.local/bin/shell_context_switcher.sh`.

Custom extensions and profiles with content are preserved during an automated uninstall. The installer will print their paths so you can remove them manually if desired.

## License

See [LICENSE](LICENSE) if available.
