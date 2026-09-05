#!/bin/zsh
set -u

repo_root=${0:A:h:h}
cd "$repo_root"

echo "timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "swift=$(swift --version 2>&1 | head -1)"
echo "xcode=$(xcodebuild -version 2>&1 | head -1)"
echo "source_lines=$(find Sources -name '*.swift' -print0 | xargs -0 wc -l | tail -1 | awk '{print $1}')"
echo "test_lines=$(find Tests -name '*.swift' -print0 | xargs -0 wc -l | tail -1 | awk '{print $1}')"
echo "async_stream_constructors=$(rg -n 'AsyncThrowingStream' Sources | wc -l | tr -d ' ')"
echo "json_serialization_sites=$(rg -n 'JSONSerialization' Sources/YagrakerCore | wc -l | tr -d ' ')"
echo "unchecked_sendable_sites=$(rg -n '@unchecked Sendable' Sources | wc -l | tr -d ' ')"
echo "height_settle_hooks=$(rg -n 'scheduleHeightSettle' Sources/Yagraker | wc -l | tr -d ' ')"

echo "test_command=swift test"
echo "release_command=swift build -c release"
