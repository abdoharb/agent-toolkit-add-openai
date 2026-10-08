#!/usr/bin/env bash
# Opt-in live check of the OpenCode role permission blocks. No model calls:
# it scaffolds a throwaway project, starts a real `opencode serve` inside it,
# and reads the runtime's resolved rules from GET /api/agent — the ruleset
# that is actually enforced, not the YAML that looks right. Requires the
# opencode v2 CLI and python3; uses a random local port and a throwaway
# password, and stops the server on exit.
#
# Why: a permission block that reads correctly is not proof it is enforced.
# opencode v2 folds `write` and `patch` into `edit` and appends them in
# order, last match wins; a trailing `patch: deny` once left the tester
# unable to write its own results.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v opencode >/dev/null 2>&1 || { echo "opencode-live: opencode not installed; skipping"; exit 0; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/toolkit-oclive.XXXXXX")"
PID=""
cleanup() { [ -z "$PID" ] || kill "$PID" 2>/dev/null || true; rm -rf "$TMP"; }
trap cleanup EXIT
fail() { printf 'opencode-live: FAIL: %s\n' "$*" >&2; exit 1; }

bash "$ROOT/bin/init.sh" --target "$TMP" --project-name live > "$TMP/init.log" 2>&1 || fail "scaffold failed"
PORT=$(( 20000 + RANDOM % 20000 ))
export OPENCODE_PASSWORD="live-$RANDOM-$RANDOM"
(cd "$TMP" && exec opencode serve --port "$PORT") > "$TMP/serve.log" 2>&1 &
PID=$!

# Retry: the first /api/agent after a cold start can come back without the
# project's roles.
for _ in $(seq 1 30); do
  if opencode api GET /api/agent --server "http://localhost:$PORT" > "$TMP/agents.json" 2>/dev/null \
    && python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if {"builder","reviewer","tester"} <= {a.get("name") for a in d.get("data",[])} else 1)' "$TMP/agents.json"; then
    break
  fi
  sleep 1
done

python3 - "$TMP/agents.json" <<'PY' || fail "live ruleset check failed (see above)"
import fnmatch, json, sys
agents = {a["name"]: a for a in json.load(open(sys.argv[1])).get("data", [])}
missing = {"builder", "reviewer", "tester"} - set(agents)
if missing:
    sys.exit(f"roles not loaded by the live server: {sorted(missing)}")

def decide(role, path):
    """Last matching `edit` rule wins, as the runtime evaluates them."""
    effect = None
    for rule in agents[role].get("permissions", []):
        if rule.get("action") != "edit":
            continue
        pattern = rule.get("resource", "")
        if pattern == "*" or fnmatch.fnmatch(path, pattern.replace("**", "*")):
            effect = rule.get("effect")
    return effect

expect = [
    ("tester", ".pipeline/T-1.md", "allow"),  # it must record its own results
    ("tester", "src/app.js", "deny"),         # and never fix source
    ("reviewer", ".pipeline/T-1.md", "deny"), # template default: blanket deny
    ("reviewer", "src/app.js", "deny"),
    ("builder", "src/app.js", "allow"),
]
bad = [(r, p, want, decide(r, p)) for r, p, want in expect if decide(r, p) != want]
for role, path, want, got in bad:
    print(f"opencode-live: {role} edit {path}: live={got}, expected={want}", file=sys.stderr)
sys.exit(1 if bad else 0)
PY
printf 'opencode-live: live OpenCode %s enforces the scaffolded role write scopes\n' "$(opencode --version 2>/dev/null)"
