# opencode-sandbox launcher. In ~/.zshrc:  source /path/to/opencode-sandbox/oc.zsh
#
# Using ponytail? Point PONYTAIL_DIR at your clone if it's not at the default.
# Skip it and the mount drops out.
#   export PONYTAIL_DIR=~/code/ponytail

# Grab this file's dir now — inside oc() $0 is the function name, not the path.
OC_SANDBOX_DIR="${${(%):-%x}:A:h}"

# opencode in a throwaway container against the current repo, using the LLM from
# your ~/.config/opencode/opencode.json. Host paths mount at their real locations
# with HOME matched, so absolute command paths in your config resolve inside the
# container. sandbox.json gives full permissions — container only.
oc() { _oc_sandbox opencode "$@"; }

# pi in the same container, using the LLM from ~/.config/pi-sandbox/models.json
# (override with PI_SANDBOX_MODELS). Never touches the host's ~/.pi/agent.
ocpi() { _oc_sandbox pi "$@"; }

_oc_sandbox() {
  local agent=$1; shift
  local ponytail="${PONYTAIL_DIR:-$HOME/Developer/_cloned/ponytail}"
  local mounts=(-v "$PWD":/workspace) env=()
  [[ -d "$ponytail" ]] && mounts+=(-v "$ponytail":"$ponytail":ro)

  if [[ $agent == opencode ]]; then
    local cfg="$OC_SANDBOX_DIR/sandbox.json"
    mounts+=(
      -v "$cfg":"$cfg":ro
      -v "$HOME/.config/opencode":"$HOME/.config/opencode":ro
      -v "$HOME/.local/state/opencode":"$HOME/.local/state/opencode":ro
    )
    env+=(-e OPENCODE_CONFIG="$cfg")
    # v2 loads plugins from a directory under `plugins`; the path is per-machine,
    # so it's injected here rather than baked into sandbox.json.
    [[ -d "$ponytail" ]] && env+=(-e OPENCODE_CONFIG_CONTENT="{\"plugins\":[\"$ponytail/.opencode/plugins\"]}")
    # v2 defaults to a shared background service registered in the state dir,
    # which here is the host's (read-only). Run a private server instead.
    # ponytail: only commands that take --standalone get it; debug/session don't.
    case ${1:-} in
      ''|-*) set -- --standalone "$@" ;;
      run|mini|models|stats) set -- "$1" --standalone "${@:2}" ;;
    esac
  else
    local models="${PI_SANDBOX_MODELS:-$HOME/.config/pi-sandbox/models.json}"
    if [[ ! -f "$models" ]]; then
      print -u2 "ocpi: $models not found; see README (pi setup)."
      return 1
    fi
    # Agent dir on a named volume keeps /model defaults between runs; sessions
    # stay ephemeral (cwd is always /workspace, so they'd mix across repos).
    mounts+=(-v pi-sandbox-agent:/pi-agent -v "$models":/pi-agent/models.json:ro)
    env+=(-e PI_CODING_AGENT_DIR=/pi-agent -e PI_CODING_AGENT_SESSION_DIR=/tmp/pi-sessions)
    [[ -d "$ponytail" ]] && set -- -e "$ponytail" "$@"
  fi

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
    -w /workspace \
    "${env[@]}" \
    "${mounts[@]}" \
    opencode-sandbox "$agent" "$@"
}
