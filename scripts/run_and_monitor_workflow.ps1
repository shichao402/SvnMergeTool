# Run and monitor GitHub Actions workflow
# Usage: .\scripts\run_and_monitor_workflow.ps1 [workflow-name] [version] [interval] [max-wait]

param(
    [string]$Workflow = "build.yml",
    [string]$Version = "",
    [int]$Interval = 10,
    [int]$MaxWait = 3600
)

function Start-Workflow {
    param([string]$WorkflowName, [string]$Ver)
    
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "Starting workflow: $WorkflowName" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""
    
    if ([string]::IsNullOrEmpty($Ver)) {
        gh workflow run $WorkflowName
    } else {
        gh workflow run $WorkflowName -f version=$Ver
    }
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to trigger workflow" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "Workflow triggered successfully" -ForegroundColor Green
    Write-Host ""
    
    # Wait for workflow to start
    Write-Host "Waiting for workflow to start..." -ForegroundColor Yellow
    Start-Sleep -Seconds 5
    
    # Get run ID
    $runs = gh run list --workflow=$WorkflowName --limit=1 --json databaseId,status
    if ($runs) {
        $runObj = $runs | ConvertFrom-Json
        return $runObj.databaseId
    } else {
        Write-Host "Failed to get run ID" -ForegroundColor Red
        exit 1
    }
}

function Monitor-Workflow {
    param(
        [string]$RunId,
        [int]$CheckInterval,
        [int]$MaxWaitTime
    )
    
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "Monitoring workflow run: $RunId" -ForegroundColor Cyan
    Write-Host "URL: https://github.com/shichao402/SvnMergeTool/actions/runs/$RunId" -ForegroundColor Cyan
    Write-Host "Check interval: $CheckInterval seconds" -ForegroundColor Cyan
    Write-Host "Max wait time: $MaxWaitTime seconds" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""
    
    $elapsed = 0
    
    while ($elapsed -lt $MaxWaitTime) {
        Start-Sleep -Seconds $CheckInterval
        $elapsed += $CheckInterval
        
        try {
            $runInfo = gh api repos/shichao402/SvnMergeTool/actions/runs/$RunId --jq '{status: .status, conclusion: .conclusion}'
            $runObj = $runInfo | ConvertFrom-Json
            $status = $runObj.status
            $conclusion = if ($runObj.conclusion) { $runObj.conclusion } else { "running" }
            
            $color = switch ($status) {
                "completed" { if ($conclusion -eq "success") { "Green" } else { "Red" } }
                "in_progress" { "Yellow" }
                default { "White" }
            }
            
            Write-Host "[$elapsed s] Status: $status, Conclusion: $conclusion" -ForegroundColor $color
            
            if ($status -eq "completed") {
                Write-Host ""
                if ($conclusion -eq "success") {
                    Write-Host "==========================================" -ForegroundColor Green
                    Write-Host "Workflow completed successfully!" -ForegroundColor Green
                    Write-Host "==========================================" -ForegroundColor Green
                    return $true
                } else {
                    Write-Host "==========================================" -ForegroundColor Red
                    Write-Host "Workflow failed: $conclusion" -ForegroundColor Red
                    Write-Host "==========================================" -ForegroundColor Red
                    return $false
                }
            }
        } catch {
            Write-Host "Error getting run status: $_" -ForegroundColor Red
        }
    }
    
    Write-Host ""
    Write-Host "Timeout: workflow execution exceeded $MaxWaitTime seconds" -ForegroundColor Yellow
    return $false
}

function Get-FailedLogs {
    param([string]$RunId)
    
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Yellow
    Write-Host "Failed Step Logs:" -ForegroundColor Yellow
    Write-Host "==========================================" -ForegroundColor Yellow
    Write-Host ""
    
    gh run view $RunId --log-failed
}

# Main execution: run -> monitor -> if failed, get logs and exit
Write-Host ""
Write-Host "==========================================" -ForegroundColor Magenta
Write-Host "Starting workflow execution" -ForegroundColor Magenta
Write-Host "==========================================" -ForegroundColor Magenta
Write-Host ""

# Step 1: Start workflow and get run ID
$runId = Start-Workflow -WorkflowName $Workflow -Ver $Version

# Step 2: Monitor workflow
$success = Monitor-Workflow -RunId $runId -CheckInterval $Interval -MaxWaitTime $MaxWait

# Step 3: If successful, exit
if ($success) {
    Write-Host ""
    Write-Host "Workflow completed successfully!" -ForegroundColor Green
    exit 0
}

# Step 4: If failed, get logs and exit (no retry loop, AI will fix and rerun)
Write-Host ""
Write-Host "Workflow failed" -ForegroundColor Red
Get-FailedLogs -RunId $runId

Write-Host ""
Write-Host "==========================================" -ForegroundColor Yellow
Write-Host "Workflow failed - logs displayed above" -ForegroundColor Yellow
Write-Host "==========================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. Review the failed logs above" -ForegroundColor White
Write-Host "2. Fix the issues in the code" -ForegroundColor White
Write-Host "3. Commit and push the fixes" -ForegroundColor White
Write-Host "4. Run this script again to retry" -ForegroundColor White
Write-Host ""

exit 1

