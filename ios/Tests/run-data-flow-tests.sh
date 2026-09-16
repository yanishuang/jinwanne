#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
workdir=$(mktemp -d /tmp/jinwanne-data-tests.XXXXXX)
fixture_pid=
cleanup() {
  if [ -n "$fixture_pid" ]; then kill "$fixture_pid" 2>/dev/null || true; wait "$fixture_pid" 2>/dev/null || true; fi
  rm -rf "$workdir"
}
trap cleanup EXIT HUP INT TERM
xcrun swiftc -swift-version 5 -parse-as-library ios/JinwanNe/Models.swift ios/JinwanNe/APIClient.swift ios/JinwanNe/AppModel.swift ios/Tests/AppModelRegression.swift -o "$workdir/model-tests"
"$workdir/model-tests"
xcrun swiftc -swift-version 5 -parse-as-library ios/JinwanNe/Models.swift ios/JinwanNe/APIClient.swift ios/Tests/APIClientIntegration.swift -o "$workdir/api-tests"
node ios/Tests/local-api-fixture.mjs "$workdir/address" > "$workdir/server.log" 2>&1 &
fixture_pid=$!
tries=0
until [ -s "$workdir/address" ]; do
  tries=$((tries + 1))
  if [ "$tries" -ge 50 ] || ! kill -0 "$fixture_pid" 2>/dev/null; then cat "$workdir/server.log"; exit 1; fi
  sleep 0.1
done
"$workdir/api-tests" "$(cat "$workdir/address")"
