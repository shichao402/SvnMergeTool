#!/bin/bash
# Test GitHub Actions workflow locally using act
# Usage: bash scripts/test_workflow_local.sh [workflow-file] [job-name]

set -e

WORKFLOW="${1:-.github/workflows/build.yml}"
JOB="${2:-}"
EVENT="${3:-workflow_dispatch}"

echo "=========================================="
echo "Testing GitHub Actions workflow locally"
echo "=========================================="
echo ""

# Check if act is installed
if ! command -v act &> /dev/null; then
    echo "act is not installed. Installing..."
    bash scripts/setup_act.sh
    if [ $? -ne 0 ]; then
        echo "Failed to install act"
        exit 1
    fi
fi

# Check if Docker is running
if ! docker ps &> /dev/null; then
    echo "Error: Docker is not running or not installed"
    echo "Please start Docker and try again"
    exit 1
fi

echo "Workflow: $WORKFLOW"
echo "Event: $EVENT"
if [ -n "$JOB" ]; then
    echo "Job: $JOB"
fi
echo ""

# List available workflows and jobs
echo "Available workflows and jobs:"
act -l -W "$WORKFLOW"
echo ""

# Run workflow
if [ -n "$JOB" ]; then
    echo "Running job: $JOB"
    act "$EVENT" -W "$WORKFLOW" -j "$JOB" --verbose
else
    echo "Running all jobs for event: $EVENT"
    act "$EVENT" -W "$WORKFLOW" --verbose
fi

