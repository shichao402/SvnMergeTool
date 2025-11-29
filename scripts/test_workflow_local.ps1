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
$dockerRunning = $false
try {
    docker ps 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        $dockerRunning = $true
    }
} catch {
    # Docker not available in PowerShell
}

# If Docker is not available in PowerShell, check WSL2
if (-not $dockerRunning) {
    $wslAvailable = Get-Command wsl -ErrorAction SilentlyContinue
    if ($wslAvailable) {
        Write-Host "Checking Docker in WSL2..." -ForegroundColor Yellow
        $wslDocker = wsl docker ps 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Docker is running in WSL2" -ForegroundColor Green
            Write-Host "Note: act will use WSL2 Docker automatically" -ForegroundColor Yellow
            $dockerRunning = $true
        }
    }
}

if (-not $dockerRunning) {
    Write-Host "Error: Docker is not running or not installed" -ForegroundColor Red
    Write-Host ""
    
    # Check if WSL2 has Docker
    $wslAvailable = Get-Command wsl -ErrorAction SilentlyContinue
    if ($wslAvailable) {
        $wslDocker = wsl docker ps 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Docker is running in WSL2, but 'act' in PowerShell cannot use it directly." -ForegroundColor Yellow
            Write-Host ""
            Write-Host "To use 'act' with WSL2 Docker, you have two options:" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "Option 1: Run 'act' from WSL2 terminal (Recommended)" -ForegroundColor Green
            Write-Host "  1. Open WSL2 terminal (Ubuntu)" -ForegroundColor White
            Write-Host "  2. Navigate to your project: cd /mnt/f/workspace/SvnMergeTool" -ForegroundColor White
            Write-Host "  3. Install act in WSL2: curl https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash" -ForegroundColor White
            Write-Host "  4. Run act: act -l" -ForegroundColor White
            Write-Host ""
            Write-Host "Option 2: Install Docker Desktop for Windows" -ForegroundColor Cyan
            Write-Host "  1. Download from: https://www.docker.com/products/docker-desktop" -ForegroundColor White
            Write-Host "  2. Install and start Docker Desktop" -ForegroundColor White
            Write-Host "  3. Wait for Docker to be ready, then try again" -ForegroundColor White
            Write-Host ""
            exit 1
        }
    }
    
    Write-Host "Please install Docker using one of these methods:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Option 1: Install Docker Desktop" -ForegroundColor Cyan
    Write-Host "  1. Download from: https://www.docker.com/products/docker-desktop" -ForegroundColor White
    Write-Host "  2. Install and start Docker Desktop" -ForegroundColor White
    Write-Host "  3. Wait for Docker to be ready, then try again" -ForegroundColor White
    Write-Host ""
    Write-Host "Option 2: Install Docker Engine in WSL2" -ForegroundColor Cyan
    Write-Host "  Run: powershell -ExecutionPolicy Bypass -File scripts\setup_docker.ps1" -ForegroundColor White
    Write-Host "  Then follow the WSL2 installation instructions" -ForegroundColor White
    Write-Host "  Note: You'll need to run 'act' from WSL2 terminal, not PowerShell" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Note: Docker is only needed for local GitHub Actions testing." -ForegroundColor Yellow
    Write-Host "If you don't need local testing, you can skip Docker installation." -ForegroundColor Yellow
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


