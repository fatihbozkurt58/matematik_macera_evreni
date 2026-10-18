# Codex repository instructions

When the user says **"Derle, test et ve ekran görüntüsünü göster"**:

1. Ensure intended changes are committed and pushed to GitHub. Do not push unrelated work. Confirm the target branch.
2. Run `bash tools/codex_capture.sh android <branch>` from an environment with authenticated GitHub CLI (`gh`) and repository Actions permission. Use `ios` or `both` only when explicitly requested.
3. The workflow runs `flutter analyze`, `flutter test`, builds the screenshot entrypoint, launches a real simulator/emulator, and uploads PNG artifacts. Do not claim production app functionality was tested by the mocked screenshot entrypoint.
4. If any step fails, read the emitted failing logs and fix the cause; repeat only after fixing it. Never report success without checking the run conclusion.
5. The script downloads PNGs to `.codex/screenshots/<run_id>/`. Open and display the image in the conversation **only if the Codex environment actually supports reading and rendering it**. Otherwise provide the exact artifact/run link and state the limitation.
6. If `gh` or GitHub Actions write access is unavailable, explain the missing capability; do not pretend to have triggered the workflow.

This uses GitHub-hosted runners, which are ephemeral. A cold build and simulator startup cannot be guaranteed to finish in seconds.
