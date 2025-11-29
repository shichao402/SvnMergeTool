# Debug GitHub Actions workflow - comprehensive debugging tool
# Usage: .\scripts\debug_workflow.ps1 [run-id] [workflow-name]

param(
    [string]$RunId = "",
    [string]$Workflow = "build.yml"
)

# If no run-id provided, get the latest run
if ([string]::IsNullOrEmpty($RunId)) {
    Write-Host "Getting latest run for workflow: $Workflow"
    $runs = gh run list --workflow=$Workflow --limit=1 --json databaseId,status,conclusion
    if ($runs) {
        $runObj = $runs | ConvertFrom-Json
        $RunId = $runObj.databaseId
        Write-Host "Using run: $RunId"
        Write-Host ""
    } else {
        Write-Host "No runs found for workflow: $Workflow"
        exit 1
    }
}

Write-Host "=========================================="
Write-Host "Workflow Debug Information"
Write-Host "=========================================="
Write-Host "Run ID: $RunId"
Write-Host ""

# Get run summary
Write-Host "=========================================="
Write-Host "Run Summary:"
Write-Host "=========================================="
$runInfo = gh run view $RunId --json status,conclusion,url,createdAt,headBranch,event
$runObj = $runInfo | ConvertFrom-Json
Write-Host "Status: $($runObj.status)"
Write-Host "Conclusion: $($runObj.conclusion)"
Write-Host "Branch: $($runObj.headBranch)"
Write-Host "Event: $($runObj.event)"
Write-Host "Created: $($runObj.createdAt)"
Write-Host "URL: $($runObj.url)"
Write-Host ""

# Get job details
Write-Host "=========================================="
Write-Host "Job Details:"
Write-Host "=========================================="
$jobs = gh run view $RunId --json jobs
$jobsObj = $jobs | ConvertFrom-Json
foreach ($job in $jobsObj.jobs) {
    Write-Host "$($job.name):"
    Write-Host "  Status: $($job.status)"
    Write-Host "  Conclusion: $($job.conclusion)"
    Write-Host "  ID: $($job.id)"
    Write-Host ""
}

# Get failed jobs
$failedJobs = $jobsObj.jobs | Where-Object { $_.conclusion -eq "failure" }

if ($failedJobs) {
    Write-Host "=========================================="
    Write-Host "Failed Jobs:"
    Write-Host "=========================================="
    foreach ($job in $failedJobs) {
        Write-Host $job.name
    }
    Write-Host ""
    
    # Get failed steps for each job
    foreach ($job in $failedJobs) {
        Write-Host "----------------------------------------"
        Write-Host "Failed Steps in: $($job.name)"
        Write-Host "----------------------------------------"
        $failedSteps = $job.steps | Where-Object { $_.conclusion -eq "failure" }
        foreach ($step in $failedSteps) {
            Write-Host "  Step $($step.number): $($step.name)"
        }
        Write-Host ""
    }
    
    # Show failed logs
    Write-Host "=========================================="
    Write-Host "Failed Step Logs:"
    Write-Host "=========================================="
    gh run view $RunId --log-failed
} else {
    Write-Host "No failed jobs found"
}

