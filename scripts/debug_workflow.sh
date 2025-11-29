#!/bin/bash
# Debug GitHub Actions workflow - comprehensive debugging tool
# Usage: ./scripts/debug_workflow.sh [run-id] [workflow-name]

set -e

RUN_ID="$1"
WORKFLOW="${2:-build.yml}"

# If no run-id provided, get the latest run
if [ -z "$RUN_ID" ]; then
    echo "Getting latest run for workflow: $WORKFLOW"
    RUN_ID=$(gh run list --workflow="$WORKFLOW" --limit=1 --json databaseId --jq '.[0].databaseId')
    
    if [ -z "$RUN_ID" ]; then
        echo "No runs found for workflow: $WORKFLOW"
        exit 1
    fi
    echo "Using run: $RUN_ID"
    echo ""
fi

echo "=========================================="
echo "Workflow Debug Information"
echo "=========================================="
echo "Run ID: $RUN_ID"
echo ""

# Get run summary
echo "=========================================="
echo "Run Summary:"
echo "=========================================="
gh run view "$RUN_ID" --json status,conclusion,url,createdAt,headBranch,event --jq '{
    status: .status,
    conclusion: .conclusion,
    branch: .headBranch,
    event: .event,
    created: .createdAt,
    url: .url
}'
echo ""

# Get job details
echo "=========================================="
echo "Job Details:"
echo "=========================================="
JOBS=$(gh run view "$RUN_ID" --json jobs --jq '.jobs[]')

echo "$JOBS" | jq -r '. | "\(.name):\n  Status: \(.status)\n  Conclusion: \(.conclusion // "running")\n  ID: \(.id)\n"'

# Get failed jobs
FAILED_JOBS=$(echo "$JOBS" | jq -r 'select(.conclusion == "failure") | .name')

if [ -n "$FAILED_JOBS" ]; then
    echo "=========================================="
    echo "Failed Jobs:"
    echo "=========================================="
    echo "$FAILED_JOBS"
    echo ""
    
    # Get failed steps for each job
    echo "$FAILED_JOBS" | while read -r job_name; do
        echo "----------------------------------------"
        echo "Failed Steps in: $job_name"
        echo "----------------------------------------"
        echo "$JOBS" | jq -r "select(.name == \"$job_name\") | .steps[] | select(.conclusion == \"failure\") | \"  Step \(.number): \(.name)\""
        echo ""
    done
    
    # Show failed logs
    echo "=========================================="
    echo "Failed Step Logs:"
    echo "=========================================="
    gh run view "$RUN_ID" --log-failed
else
    echo "No failed jobs found"
fi

