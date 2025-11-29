# Test GitHub Actions workflow locally using act
# Usage: .\scripts\test_workflow_local.ps1 [workflow-file] [job-name]

param(
    [string]$Workflow = ".github/workflows/build.yml",
    [string]$Job = "",
    [string]$Event = "workflow_dispatch"
)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Testing GitHub Actions workflow locally" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Check if act is installed
$actInstalled = Get-Command act -ErrorAction SilentlyContinue

if (-not $actInstalled) {
    Write-Host "act is not installed. Installing..." -ForegroundColor Yellow
    powershell -ExecutionPolicy Bypass -File scripts\setup_act.ps1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to install act" -ForegroundColor Red
        exit 1
    }
}

# Check if Docker is running
try {
    docker ps | Out-Null
} catch {
    Write-Host "Error: Docker is not running or not installed" -ForegroundColor Red
    Write-Host "Please start Docker Desktop and try again" -ForegroundColor Yellow
    exit 1
}

Write-Host "Workflow: $Workflow" -ForegroundColor Cyan
Write-Host "Event: $Event" -ForegroundColor Cyan
if ($Job) {
    Write-Host "Job: $Job" -ForegroundColor Cyan
}
Write-Host ""

# List available workflows and jobs
Write-Host "Available workflows and jobs:" -ForegroundColor Yellow
act -l -W $Workflow
Write-Host ""

# Run workflow
if ($Job) {
    Write-Host "Running job: $Job" -ForegroundColor Green
    act $Event -W $Workflow -j $Job --verbose
} else {
    Write-Host "Running all jobs for event: $Event" -ForegroundColor Green
    act $Event -W $Workflow --verbose
}

