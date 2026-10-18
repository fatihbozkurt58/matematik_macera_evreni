#!/bin/bash
set -eu
cd "$(dirname "$0")/.."
if [ "${GCLOUD_PROJECT:-}" != "demo-matematik-evreni" ]; then
  echo 'Refusing a non-demo Firebase project.' >&2
  exit 1
fi
for emulator_port in 9099 8080 5001 9199; do
  adb -s "$1" reverse "tcp:$emulator_port" "tcp:$emulator_port"
done
node tool/firebase_device_fixture.mjs
.fvm/flutter_sdk/bin/flutter test --no-uninstall integration_test/session_foundation_test.dart --flavor dev -d "$1" --dart-define=USE_LOCAL_FIREBASE_EMULATORS=true --dart-define=ENABLE_DEV_TEST_ACCOUNTS=true

for phase in seed restore forget; do
  adb -s "$1" shell am force-stop com.fatihbozkurt.matematik.dev
  .fvm/flutter_sdk/bin/flutter test --no-uninstall integration_test/session_foundation_test.dart --flavor dev -d "$1" --dart-define=USE_LOCAL_FIREBASE_EMULATORS=true --dart-define=ENABLE_DEV_TEST_ACCOUNTS=true --dart-define=SESSION_TEST_PHASE="$phase"
done
