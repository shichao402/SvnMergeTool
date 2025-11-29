#!/bin/bash
# Debug GitHub Actions Workflow Failure
# Get detailed information about failed workflow runs

set -e

RUN_ID="${1:-}"

if [ -z "$RUN_ID" ]; then
    echo "Usage: $0 <run-id>"
    echo "Or: $0 (will get latest failed run)"
    exit 1
fi

if [ "$RUN_ID" = "latest" ]; then
    echo "Getting latest failed run..."
    RUN_ID=$(gh run list --workflow=build.yml --limit=10 --json databaseId,conclusion --jq '.[] | select(.conclusion == "failure") | .databaseId' | head -1)
    
    if [ -z "$RUN_ID" ]; then
        echo "No failed runs found"
        exit 1
    fi
    echo "Found failed run: $RUN_ID"
fi

echo "=========================================="
echo "Debugging Workflow Run: $RUN_ID"
echo "=========================================="
echo ""

# Get run info
echo "Run Information:"
gh run view "$RUN_ID" --json status,conclusion,createdAt,url,headBranch --jq '{status: .status, conclusion: .conclusion, created_at: .createdAt, url: .url, branch: .headBranch}'
echo ""

# Get job summary
echo "=========================================="
echo "Job Summary:"
echo "=========================================="
gh run view "$RUN_ID" --json jobs --jq '.jobs[] | "\(.name): \(.status) - \(.conclusion // "running")"'
echo ""

# Get failed jobs
echo "=========================================="
echo "Failed Jobs:"
echo "=========================================="
FAILED_JOBS=$(gh run view "$RUN_ID" --json jobs --jq '.jobs[] | select(.conclusion == "failure") | .name')

if [ -z "$FAILED_JOBS" ]; then
    echo "No failed jobs found"
else
    echo "$FAILED_JOBS"
    echo ""
    
    # Get failed steps for each job
    for JOB_NAME in $FAILED_JOBS; do
        echo "----------------------------------------"
        echo "Failed Steps in: $JOB_NAME"
        echo "----------------------------------------"
        gh run view "$RUN_ID" --json jobs --jq ".jobs[] | select(.name == \"$JOB_NAME\") | .steps[] | select(.conclusion == \"failure\") | \"  Step \(.number): \(.name)\""
        echo ""
    done
fi

# Get error logs
echo "=========================================="
echo "Error Logs (first 50 lines):"
echo "=========================================="
gh run view "$RUN_ID" --log-failed 2>&1 | head -50

echo ""
echo "=========================================="
echo "View full logs:"
echo "gh run view $RUN_ID --log-failed"
echo "=========================================="


