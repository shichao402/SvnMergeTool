#!/bin/bash
# View logs for a specific job
# Usage: ./scripts/view_job_logs.sh <run-id> <job-name> [--failed-only]

set -e

RUN_ID="$1"
JOB_NAME="$2"
FAILED_ONLY="$3"

if [ -z "$RUN_ID" ] || [ -z "$JOB_NAME" ]; then
    echo "Usage: $0 <run-id> <job-name> [--failed-only]"
    echo "Example: $0 19785821359 'Build macOS' --failed-only"
    exit 1
fi

# Get job ID
JOB_ID=$(gh run view "$RUN_ID" --json jobs --jq ".jobs[] | select(.name == \"$JOB_NAME\") | .id")

if [ -z "$JOB_ID" ]; then
    echo "Job '$JOB_NAME' not found in run $RUN_ID"
    exit 1
fi

echo "=========================================="
echo "Logs for Job: $JOB_NAME (ID: $JOB_ID)"
echo "=========================================="
echo ""

if [ "$FAILED_ONLY" = "--failed-only" ]; then
    gh run view "$RUN_ID" --job "$JOB_ID" --log-failed
else
    gh run view "$RUN_ID" --job "$JOB_ID" --log
fi

