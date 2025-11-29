#!/bin/bash
# View failed logs from GitHub Actions workflow run
# Usage: ./scripts/view_failed_logs.sh [run-id] [workflow-name]

set -e

RUN_ID="$1"
WORKFLOW="${2:-build.yml}"

# If no run-id provided, get the latest failed run
if [ -z "$RUN_ID" ]; then
    echo "Getting latest failed run for workflow: $WORKFLOW"
    RUN_ID=$(gh run list --workflow="$WORKFLOW" --limit=10 --json databaseId,conclusion --jq '.[] | select(.conclusion == "failure") | .databaseId' | head -1)
    
    if [ -z "$RUN_ID" ]; then
        echo "No failed runs found for workflow: $WORKFLOW"
        exit 1
    fi
    echo "Found failed run: $RUN_ID"
    echo ""
fi

echo "=========================================="
echo "Failed Logs for Run: $RUN_ID"
echo "=========================================="
echo ""

# Get run info
RUN_INFO=$(gh run view "$RUN_ID" --json status,conclusion,url,createdAt)
echo "$RUN_INFO" | jq -r '"Status: \(.status)\nConclusion: \(.conclusion)\nURL: \(.url)\nCreated: \(.createdAt)\n"'

# Get job summary
echo "=========================================="
echo "Job Summary:"
echo "=========================================="
gh run view "$RUN_ID" --json jobs --jq '.jobs[] | "\(.name): \(.status) - \(.conclusion // "running")"'
echo ""

# View failed logs
echo "=========================================="
echo "Failed Step Logs:"
echo "=========================================="
gh run view "$RUN_ID" --log-failed
