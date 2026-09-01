# opencode-sandbox launcher. In ~/.zshrc:  source /path/to/opencode-sandbox/oc.zsh
#
# Using ponytail? Point PONYTAIL_DIR at your clone if it's not at the default.
# Skip it and the mount drops out.
#   export PONYTAIL_DIR=~/code/ponytail

# Grab this file's dir now — inside oc() $0 is the function name, not the path.
OC_SANDBOX_DIR="${${(%):-%x}:A:h}"

# opencode in a throwaway container against the current repo, using the LLM from
# your ~/.config/opencode/opencode.json. Host paths mount at their real locations
# with HOME matched, so absolute plugin/command paths in your config resolve
# inside the container. sandbox.json gives full permissions — container only.
oc() {
  # Rebuild the image on every invocation so the opencode-ai version stays fresh.
  docker build -t opencode-sandbox "$OC_SANDBOX_DIR" >/dev/null 2>&1

  local cfg="$OC_SANDBOX_DIR/sandbox.json"
  local tui_cfg="$OC_SANDBOX_DIR/tui.json"
  local ponytail="${PONYTAIL_DIR:-$HOME/Developer/_cloned/ponytail}"

  local mounts=(
    -v "$cfg":"$cfg":ro
    -v "$tui_cfg":"$tui_cfg":ro
    -v "$PWD":/workspace
    -v "$HOME/.config/opencode":"$HOME/.config/opencode":ro
    -v "$HOME/.local/state/opencode":"$HOME/.local/state/opencode":ro
  )
  [[ -d "$ponytail" ]] && mounts+=(-v "$ponytail":"$ponytail":ro)

  # Python repo? Give it a container-native .venv on a per-repo named volume,
  # mounted over /workspace/.venv. The host's .venv (Mac-built, useless in Linux)
  # is shadowed and untouched; the container's persists across runs. Create it
  # once inside: python3 -m venv .venv && pip install -e ".[dev]"
  if [[ -f "$PWD/pyproject.toml" || -f "$PWD/requirements.txt" || -d "$PWD/.venv" ]]; then
    local vol
    vol="ocvenv-$(print -rn -- "$PWD" | cksum | cut -d' ' -f1)"
    mounts+=(-v "$vol":/workspace/.venv)
  fi

  docker run --rm -it \
    -e HOME="$HOME" \
    -e OPENCODE_CONFIG="$cfg" \
    -e OPENCODE_TUI_CONFIG="$tui_cfg" \
    -w /workspace \
    "${mounts[@]}" \
    opencode-sandbox "$@"
}
