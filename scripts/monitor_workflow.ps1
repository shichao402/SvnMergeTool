# Monitor GitHub Actions workflow until completion
# Usage: .\scripts\monitor_workflow.ps1 [run-id] [workflow-name] [interval-seconds]

param(
    [string]$RunId = "",
    [string]$Workflow = "build.yml",
    [int]$Interval = 10,
    [int]$MaxWait = 3600
)

# If no run-id provided, get the latest run
if ([string]::IsNullOrEmpty($RunId)) {
    Write-Host "Getting latest run for workflow: $Workflow"
    $runs = gh run list --workflow=$Workflow --limit=1 --json databaseId,status,conclusion
    if ($runs) {
        $runObj = $runs | ConvertFrom-Json
        $RunId = $runObj.databaseId
        Write-Host "Monitoring run: $RunId"
        Write-Host "URL: https://github.com/shichao402/SvnMergeTool/actions/runs/$RunId"
        Write-Host ""
    } else {
        Write-Host "No runs found for workflow: $Workflow"
        exit 1
    }
}

$elapsed = 0
$startTime = Get-Date

Write-Host "Monitoring workflow run: $RunId"
Write-Host "Check interval: $Interval seconds"
Write-Host "Max wait time: $MaxWait seconds"
Write-Host ""

while ($elapsed -lt $MaxWait) {
    Start-Sleep -Seconds $Interval
    $elapsed += $Interval
    
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
                Write-Host "Workflow completed successfully!" -ForegroundColor Green
                exit 0
            } else {
                Write-Host "Workflow failed: $conclusion" -ForegroundColor Red
                Write-Host ""
                Write-Host "Viewing failed logs..." -ForegroundColor Yellow
                gh run view $RunId --log-failed
                exit 1
            }
        }
    } catch {
        Write-Host "Error getting run status: $_" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Timeout: workflow execution exceeded $MaxWait seconds" -ForegroundColor Yellow
exit 1
