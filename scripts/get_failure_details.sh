#!/bin/bash
# Get detailed failure information from a workflow run

RUN_ID="$1"
STEP_NAME="${2:-}"

if [ -z "$RUN_ID" ]; then
    echo "Usage: $0 <run-id> [step-name]"
    exit 1
fi

echo "Getting failure details for run: $RUN_ID"
echo ""

# Get all jobs
JOBS=$(gh run view "$RUN_ID" --json jobs --jq '.jobs[]')

echo "$JOBS" | jq -r '.name as $job | .steps[] | select(.conclusion == "failure") | "Job: \($job)\nStep: \(.name)\nNumber: \(.number)\n"'

# If step name provided, get its log
if [ -n "$STEP_NAME" ]; then
    echo "=========================================="
    echo "Log for step: $STEP_NAME"
    echo "=========================================="
    
    JOB_ID=$(echo "$JOBS" | jq -r '.[0].id')
    gh run view "$RUN_ID" --job "$JOB_ID" --log | grep -A 50 -B 10 "$STEP_NAME" || true
fi


