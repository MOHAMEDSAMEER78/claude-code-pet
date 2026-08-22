#!/bin/bash
set -euo pipefail

LOG_FILE="${1:?usage: summarize-tests.sh <log-file>}"

if [ ! -s "$LOG_FILE" ]; then
    echo "## Test Results"
    echo ""
    echo "⚠️ No test output captured (\`$LOG_FILE\` is empty)."
    exit 0
fi

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
        grep -F "✘ Test $TEST_NAME " "$LOG_FILE" | grep "recorded an issue at" | sed -E 's/^✘ Test .+ recorded an issue at /  /' || true
        echo '```'
        echo ""
        echo "</details>"
    done <<< "$FAILED_TESTS"
fi

exit 0
