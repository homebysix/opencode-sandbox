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
  local mounts=(-v "$PWD":/workspace) env=() oc_config=
  [[ -d "$ponytail" ]] && mounts+=(-v "$ponytail":"$ponytail":ro)

  if [[ $agent == opencode ]]; then
    # Read the REAL host plugin list, but drop Mac-only local (path-based) plugins
    # so they don't fail loading in Linux; keep named/git plugins (superpowers@...).
    # Merge that filtered list over sandbox.json's permission layer into a one-off
    # config the container reads as OPENCODE_CONFIG. Your host config is untouched.
    local cfg="$OC_SANDBOX_DIR/sandbox.json"
    local oc_host="$HOME/.config/opencode/opencode.json"
    # One-off overlay config, written to a throwaway temp file and removed on exit.
    oc_config="$(mktemp)"
    if [[ -f "$oc_host" ]]; then
      python3 - "$cfg" "$oc_host" "$oc_config" <<'PY'
import json, sys
sandbox = json.load(open(sys.argv[1]))
host = json.load(open(sys.argv[2]))
keep = [p for p in (host.get("plugin") or [])
        if not (isinstance(p, str) and p.startswith(("./", "../", "/")))]
out = dict(sandbox); out["plugin"] = keep
json.dump(out, open(sys.argv[3], "w"), indent=2)
open(sys.argv[3], "a").write("\n")
PY
    else
      # No host config: fall back to sandbox.json unchanged (no plugins filtered).
      cp "$cfg" "$oc_config"
    fi
    mounts+=(
      -v "$oc_config":"$oc_config":ro
      -v "$HOME/.config/opencode":"$HOME/.config/opencode":ro
      # State (locks, sessions db, auth cache) must be writable, so shadow the
      # host's read-only copy with an anonymous container volume. Ephemeral per
      # run; clean up occasionally with `docker volume prune` (like the venv vols).
      -v "$HOME/.local/state/opencode"
    )
    env+=(-e OPENCODE_CONFIG="$oc_config")
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
    # Read the REAL host pi config read-only; never mount ~/.pi/agent writable.
    # pi still has to drop per-run lock files and a session dir, so those go into
    # the writable pi-sandbox-agent volume (plus /tmp) — your host files stay intact.
    # A plain volume over the whole dir would start empty, so each config file is
    # overlaid individually to keep it truly read-only (default model still sticks
    # in the volume; sessions are ephemeral because cwd is always /workspace).
    local ad="${PI_SANDBOX_AGENT:-$HOME/.pi/agent}"
    if [[ ! -d "$ad" ]]; then
      print -u2 "ocpi: $ad not found; is pi installed?"
      return 1
    fi
    mounts+=(-v pi-sandbox-agent:/pi-agent)
    local f
    for f in models.json settings.json auth.json; do
      [[ -f "$ad/$f" ]] && mounts+=(-v "$ad/$f":"/pi-agent/$f":ro)
    done
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
    [[ -n "$oc_config" ]] && rm -f "$oc_config"
}
