# opencode-sandbox

Run [opencode] in a throwaway Docker container against whatever repo you're in, pointed at a self-hosted OpenAI-compatible LLM (oMLX, LM Studio, Ollama — anything that speaks the OpenAI API).

## Setup (once per Mac)

Clone this anywhere, then from inside it:

```sh
docker build -t opencode-sandbox .
echo "source $PWD/oc.zsh" >> ~/.zshrc && exec zsh
```

`oc.zsh` finds its own directory, so the repo can live wherever.

You bring your own `~/.config/opencode/opencode.json` with a provider pointing at your LLM. ponytail is optional — if you use it, set `PONYTAIL_DIR` to your clone (default `~/Developer/_cloned/ponytail`) and make sure the `plugin` path in your config matches. The launcher mounts that dir so the absolute path resolves inside the container. No ponytail dir, no problem — it's skipped.

## Use

```sh
cd ~/any/repo
oc                 # opencode TUI, scoped to this repo
oc run "..."       # args pass straight through
```

## How it works

- `--rm` plus only `$PWD` mounted at `/workspace` — nothing else is reachable.
- Host paths are mounted at their **real** locations with `HOME` set to match, so the `plugin` path and `command/` symlinks in your global config resolve the same inside the container. ponytail and its `/ponytail*` commands work with no extra config.
- The LLM lives on another machine; the container reaches it over the network via the `baseURL` in `opencode.json`. Use an IP or a name the *container* can resolve — host-only names won't work inside it.

## Permissions

Permissions are configured in `opencode.json`. The sandbox layers `sandbox.json` (everything `allow`) over your global config via `OPENCODE_CONFIG`, so the container runs full-permission while your host config keeps its `ask`/`deny` guardrails.

Check the merged result anytime (from this repo):

```sh
docker run --rm -e HOME="$HOME" \
  -e OPENCODE_CONFIG="$PWD/sandbox.json" \
  -v "$PWD/sandbox.json":"$PWD/sandbox.json":ro \
  -v "$HOME/.config/opencode":"$HOME/.config/opencode" \
  opencode-sandbox debug config | jq .permission
```

## Tools in the image

`git`, `ripgrep`, `jq`, `curl`, and Python 3 (`pip` + `venv`, 3.11 from Debian bookworm). Edits land in the host repo through the `/workspace` mount; commit and push from the Mac.

Use a venv or `--break-system-packages` for throwaway installs (Debian enforces PEP 668).

## Python venvs

Mac `.venv`s aren't compatible with the container (different OS, different Python paths). For repos with a `pyproject.toml`, `requirements.txt`, or existing `.venv`, `oc` mounts a per-repo named volume over `/workspace/.venv`. That shadows the host's `.venv` (which stays untouched on disk) and gives the container its own, persisted across runs. `/workspace/.venv/bin` is on `PATH`, so it auto-activates.

Your host `.venv` content is never touched — the volume shadows it inside the container. (A repo with no `.venv` will get an empty `.venv/` stub on the host as the mount point; usually gitignored.)

Build it once inside the sandbox:

```sh
python3 -m venv .venv && pip install -e ".[dev]"   # or -r requirements.txt
```

After that `python`, `pytest`, etc. resolve to the venv on every run.

Each Python repo gets its own volume (`ocvenv-<hash>`), and they persist, so clean them up now and then:

```sh
docker volume ls -q | grep '^ocvenv-'                          # list them
docker system df -v | grep ocvenv-                             # see their size
for v in $(docker volume ls -q | grep '^ocvenv-'); do docker volume rm "$v"; done   # remove all
```

Removing one just means the next `oc` in that repo rebuilds it with the one-time command above. Close any running session before removing its volume.

## Notes / ceilings

- Your `~/.config/opencode` is mounted **read-only**, so sessions can't modify the host config. Trade-off: ponytail mode resets each session (`/ponytail <mode>` doesn't persist).
- opencode's data dir (`~/.local/share/opencode`, auth/cache) is ephemeral per run. No auth needed for a local provider, so it doesn't matter. Add a named volume if you switch to an authenticated one.
- Everything keys off `$HOME` and `$PWD`, so usernames and home paths don't need to match across machines. The one per-user coupling: the absolute `plugin` path (and any `command/` symlink targets) in your global config have to point at the same place as `PONYTAIL_DIR`.

[opencode]: https://opencode.ai
