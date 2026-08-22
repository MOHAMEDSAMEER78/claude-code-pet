#!/bin/bash
# Turns `swift test` output into a GitHub Actions job summary: pass/fail
# counts up top, then every failing test's assertion and file:line pulled
# out individually, so "test failed" in the Checks tab doesn't mean digging
# through a multi-thousand-line raw log to find out what actually broke.
#
# Parses swift-testing's console format (◇/✔/✘ prefixed lines) - the
# library this repo's tests use. Falls back to a generic error grep if that
# format isn't found, so a differently-shaped failure still surfaces
# something instead of a silent "see the log" summary.
set -euo pipefail

LOG_FILE="${1:?usage: summarize-tests.sh <log-file>}"

if [ ! -s "$LOG_FILE" ]; then
    echo "## Test Results"
    echo ""
    echo "⚠️ No test output captured (\`$LOG_FILE\` is empty)."
    exit 0
fi

# The final "Test run with N tests in M suites passed/failed after Xs[ with
# K issue(s)]." line - swift-testing always prints exactly one of these.
SUMMARY_LINE=$(grep -E 'Test run with [0-9]+ tests? in [0-9]+ suites? (passed|failed) after' "$LOG_FILE" | tail -1 || true)

echo "## Test Results"
echo ""

if [ -z "$SUMMARY_LINE" ]; then
    echo "⚠️ Couldn't find a swift-testing summary line in the output - showing raw errors instead:"
    echo ""
    echo '```'
    grep -iE "error:|fatal error|failed" "$LOG_FILE" | head -50 || echo "(no obviously-failing lines found either - see the full log)"
    echo '```'
    exit 0
fi

TOTAL=$(echo "$SUMMARY_LINE" | grep -oE '[0-9]+ tests?' | grep -oE '[0-9]+' | head -1)
SUITES=$(echo "$SUMMARY_LINE" | grep -oE '[0-9]+ suites?' | grep -oE '[0-9]+' | head -1)
DURATION=$(echo "$SUMMARY_LINE" | grep -oE 'after [0-9.]+ seconds' | grep -oE '[0-9.]+')

# Every failed test gets its own "✘ Test <name> failed after Xs with N
# issue(s)." line in addition to the one overall "Test run with N tests in
# M suites failed..." summary line above - excluded here since it matches
# the same "✘ Test ... failed after ... with N issue" shape otherwise.
FAILED_TESTS=$(grep -E '^✘ Test .+ failed after [0-9.]+ seconds? with [0-9]+ issue' "$LOG_FILE" | grep -v '^✘ Test run with [0-9]' || true)
FAILED_COUNT=$(echo "$FAILED_TESTS" | grep -c '.' || true)

if echo "$SUMMARY_LINE" | grep -q ' passed after'; then
    echo "### ✅ All tests passed"
    echo ""
    echo "| Tests | Suites | Duration |"
    echo "|---|---|---|"
    echo "| $TOTAL | $SUITES | ${DURATION}s |"
else
    PASSED=$((TOTAL - FAILED_COUNT))
    echo "### ❌ $FAILED_COUNT of $TOTAL tests failed"
    echo ""
    echo "| Passed | Failed | Suites | Duration |"
    echo "|---|---|---|---|"
    echo "| $PASSED | $FAILED_COUNT | $SUITES | ${DURATION}s |"
    echo ""
    echo "### Failures"
    echo ""
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        TEST_NAME=$(echo "$line" | sed -E 's/^✘ Test (.+) failed after.*/\1/')
        echo "<details><summary>❌ <code>$TEST_NAME</code></summary>"
        echo ""
        echo '```'
        # Every "recorded an issue at file:line:col: <message>" line for
        # this specific test name - the actual expectation that failed.
        grep -F "✘ Test $TEST_NAME " "$LOG_FILE" | grep "recorded an issue at" | sed -E 's/^✘ Test .+ recorded an issue at /  /' || true
        echo '```'
        echo ""
        echo "</details>"
    done <<< "$FAILED_TESTS"
fi

# This script's own exit code is purely "did the summary render" - whether
# the actual test run passed/failed is decided by the workflow step that
# invoked `swift test`, not by this script re-deriving it from the log.
exit 0
