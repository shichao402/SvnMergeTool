#!/bin/bash
# GitHub Actions Workflow Trigger Script
# Trigger a workflow and optionally monitor its execution

set -e

WORKFLOW="${1:-build.yml}"
VERSION="${2:-}"
MONITOR="${3:-false}"

echo "=========================================="
echo "Triggering workflow: $WORKFLOW"
echo "=========================================="
echo ""

if [ -n "$VERSION" ]; then
    echo "Using version: $VERSION"
    gh workflow run "$WORKFLOW" -f version="$VERSION"
else
    gh workflow run "$WORKFLOW"
fi

if [ "$?" -ne 0 ]; then
    echo "Failed to trigger workflow"
    exit 1
fi

echo "Workflow triggered successfully"
echo ""

if [ "$MONITOR" = "true" ] || [ "$MONITOR" = "1" ]; then
    echo "Waiting for workflow to start..."
    sleep 5
    
    # Get latest run ID
    RUN_ID=$(gh run list --workflow="$WORKFLOW" --limit=1 --json databaseId --jq '.[0].databaseId')
    
    if [ -z "$RUN_ID" ] || [ "$RUN_ID" = "null" ]; then
        echo "Failed to get run ID"
        exit 1
    fi
    
    echo "Monitoring run: $RUN_ID"
    echo "URL: https://github.com/shichao402/SvnMergeTool/actions/runs/$RUN_ID"
    echo ""
    
    # Monitor until completion
    MAX_WAIT=600
    ELAPSED=0
    INTERVAL=15
    
    while [ $ELAPSED -lt $MAX_WAIT ]; do
        sleep $INTERVAL
        ELAPSED=$((ELAPSED + INTERVAL))
        
        STATUS=$(gh api repos/shichao402/SvnMergeTool/actions/runs/$RUN_ID --jq -r '.status')
        CONCLUSION=$(gh api repos/shichao402/SvnMergeTool/actions/runs/$RUN_ID --jq -r '.conclusion // "running"')
        
        echo "[${ELAPSED}s] Status: $STATUS, Conclusion: $CONCLUSION"
        
        if [ "$STATUS" = "completed" ]; then
            echo ""
            if [ "$CONCLUSION" = "success" ]; then
                echo "Workflow completed successfully!"
                exit 0
            else
                echo "Workflow failed: $CONCLUSION"
                echo "View logs: gh run view $RUN_ID --log-failed"
                exit 1
            fi
        fi
    done
    
    echo "Timeout: workflow execution exceeded $MAX_WAIT seconds"
    exit 1
fi


