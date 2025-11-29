#!/bin/bash
# Get failed steps from a workflow run

RUN_ID="$1"

if [ -z "$RUN_ID" ]; then
    echo "Usage: $0 <run-id>"
    exit 1
fi

echo "Getting failed steps for run: $RUN_ID"
echo ""

gh run view "$RUN_ID" --json jobs --jq '.jobs[] | {job: .name, failed_steps: [.steps[] | select(.conclusion == "failure") | {name: .name, number: .number}]}'


