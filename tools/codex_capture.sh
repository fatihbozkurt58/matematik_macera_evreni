#!/usr/bin/env bash
# Trigger the GitHub Actions build/test/simulator screenshot pipeline and fetch its results.
set -euo pipefail
REPO="fatihbozkurt58/matematik-macera-evreni"
WORKFLOW="capture-screenshots.yml"
PLATFORM="${1:-android}"
REF="${2:-main}"
case "$PLATFORM" in android|ios|both) ;; *) echo "Usage: bash tools/codex_capture.sh [android|ios|both] [branch]" >&2; exit 2;; esac
command -v gh >/dev/null || { echo "GitHub CLI (gh) is required." >&2; exit 2; }
gh auth status >/dev/null 2>&1 || { echo "Authenticate gh first (gh auth login or GH_TOKEN)." >&2; exit 2; }
mkdir -p .codex/screenshots
before="$(gh run list --repo "$REPO" --workflow "$WORKFLOW" --event workflow_dispatch --branch "$REF" --limit 30 --json databaseId --jq '.[].databaseId' || true)"
echo "Dispatching $WORKFLOW on $REF ($PLATFORM)..."
gh workflow run "$WORKFLOW" --repo "$REPO" --ref "$REF" -f "platform=$PLATFORM"
run_id=""
for attempt in $(seq 1 24); do
  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    if ! grep -qx "$id" <<< "$before"; then run_id="$id"; break; fi
  done < <(gh run list --repo "$REPO" --workflow "$WORKFLOW" --event workflow_dispatch --branch "$REF" --limit 30 --json databaseId --jq '.[].databaseId')
  [[ -n "$run_id" ]] && break
  sleep 5
done
[[ -n "$run_id" ]] || { echo "Workflow was dispatched but its run ID could not be resolved. Inspect GitHub Actions." >&2; exit 1; }
echo "Run: https://github.com/$REPO/actions/runs/$run_id"
if ! gh run watch "$run_id" --repo "$REPO" --exit-status; then
  echo "Build/test failed; inspect job logs:" >&2
  gh run view "$run_id" --repo "$REPO" --log-failed || true
  exit 1
fi
gh run download "$run_id" --repo "$REPO" --dir ".codex/screenshots/$run_id"
echo "Screenshots:"
find ".codex/screenshots/$run_id" -type f -name '*.png' -print
echo "Run: https://github.com/$REPO/actions/runs/$run_id"
