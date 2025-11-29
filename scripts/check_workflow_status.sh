#!/bin/bash
# GitHub Actions Workflow Status Checker
# Check the status of the latest workflow run

set -e

WORKFLOW="${1:-build.yml}"
LIMIT="${2:-1}"

echo "=========================================="
echo "Checking workflow: $WORKFLOW"
echo "=========================================="
echo ""

# Get latest run
RUNS=$(gh run list --workflow="$WORKFLOW" --limit="$LIMIT" --json databaseId,status,conclusion,url,createdAt)

if [ -z "$RUNS" ] || [ "$RUNS" == "[]" ]; then
    echo "No runs found for workflow: $WORKFLOW"
    exit 1
fi

# Parse and display
echo "$RUNS" | jq -r '.[] | "Run ID: \(.databaseId)\nStatus: \(.status)\nConclusion: \(.conclusion // "in_progress")\nURL: \(.url)\nCreated: \(.createdAt)\n"'

# Get job details
RUN_ID=$(echo "$RUNS" | jq -r '.[0].databaseId')
echo "=========================================="
echo "Job Details:"
echo "=========================================="
gh run view "$RUN_ID" --json jobs --jq '.jobs[] | "\(.name): \(.status) - \(.conclusion // "running")"'


