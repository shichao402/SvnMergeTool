# Setup Docker for Windows
# Usage: powershell -ExecutionPolicy Bypass -File scripts\setup_docker.ps1
#
# Note: Docker is required for running 'act' tool to test GitHub Actions locally.
# If you don't need local GitHub Actions testing, you can skip Docker installation.

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Setting up Docker for Windows" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Docker is required for local GitHub Actions testing with 'act' tool." -ForegroundColor Yellow
Write-Host "If you don't need local testing, you can skip this installation." -ForegroundColor Yellow
Write-Host ""

# First, check if WSL2 has Docker (most common case for Windows users with WSL2)
$wslAvailable = Get-Command wsl -ErrorAction SilentlyContinue
if ($wslAvailable) {
    Write-Host "Checking WSL2 for Docker Engine..." -ForegroundColor Yellow
    $wslDockerVersion = wsl docker --version 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Docker Engine is installed in WSL2" -ForegroundColor Green
        Write-Host $wslDockerVersion -ForegroundColor White
        
        # Check if Docker daemon is running in WSL2
        Write-Host ""
        Write-Host "Checking if Docker daemon is running in WSL2..." -ForegroundColor Yellow
        $wslDockerPs = wsl docker ps 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Docker daemon is running in WSL2" -ForegroundColor Green
            Write-Host ""
            Write-Host "Docker is ready! You can use it with 'wsl docker' commands." -ForegroundColor Green
            Write-Host "The 'act' tool should automatically detect WSL2 Docker." -ForegroundColor Yellow
            exit 0
        } else {
            Write-Host "Docker Engine is installed but daemon is not running" -ForegroundColor Yellow
            Write-Host "Starting Docker daemon in WSL2..." -ForegroundColor Yellow
            wsl sudo service docker start 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Docker daemon started successfully" -ForegroundColor Green
                Write-Host ""
                Write-Host "Docker is ready! You can use it with 'wsl docker' commands." -ForegroundColor Green
                exit 0
            } else {
                Write-Host "Failed to start Docker daemon. Please run in WSL2:" -ForegroundColor Red
                Write-Host "  sudo service docker start" -ForegroundColor White
                exit 1
            }
        }
    }
}

# Check if Docker is installed in PowerShell (Docker Desktop)
try {
    $dockerVersion = docker --version 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Docker is already installed" -ForegroundColor Green
        Write-Host $dockerVersion -ForegroundColor White
        
        # Check if Docker daemon is running
        Write-Host ""
        Write-Host "Checking if Docker daemon is running..." -ForegroundColor Yellow
        docker ps 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Docker daemon is running" -ForegroundColor Green
            exit 0
        } else {
            Write-Host "Docker is installed but daemon is not running" -ForegroundColor Yellow
            Write-Host "Please start Docker Desktop and try again" -ForegroundColor White
            exit 1
        }
    }
} catch {
    # Docker is not installed in PowerShell
}

Write-Host "Docker is not installed. Attempting to install..." -ForegroundColor Yellow
Write-Host ""

# Try to install using Scoop
$scoopInstalled = Get-Command scoop -ErrorAction SilentlyContinue
if ($scoopInstalled) {
    Write-Host "Found Scoop. Installing Docker Desktop using Scoop..." -ForegroundColor Yellow
    Write-Host "This may take several minutes..." -ForegroundColor Yellow
    Write-Host ""
    
    try {
        scoop install docker-desktop
        if ($LASTEXITCODE -eq 0) {
            Write-Host ""
            Write-Host "Docker Desktop installed successfully!" -ForegroundColor Green
            Write-Host "Please start Docker Desktop and wait for it to be ready, then run this script again to verify." -ForegroundColor Yellow
            Write-Host ""
            Write-Host "You can start Docker Desktop by:" -ForegroundColor Cyan
            Write-Host "  1. Opening Docker Desktop from Start Menu" -ForegroundColor White
            Write-Host "  2. Or running: Start-Process 'C:\Program Files\Docker\Docker\Docker Desktop.exe'" -ForegroundColor White
            exit 0
        }
    } catch {
        Write-Host "Failed to install Docker Desktop using Scoop" -ForegroundColor Red
    }
}

# If automatic installation failed, provide manual installation instructions
Write-Host ""
Write-Host "Automatic installation is not available. Please choose an installation method:" -ForegroundColor Yellow
Write-Host ""

# Check if WSL2 is available
$wslAvailable = Get-Command wsl -ErrorAction SilentlyContinue
if ($wslAvailable) {
    Write-Host "Option 1: Install Docker Engine in WSL2 (Recommended if you have WSL2)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Quick install using script:" -ForegroundColor Yellow
    Write-Host "    wsl bash scripts/setup_docker_wsl2.sh" -ForegroundColor White
    Write-Host ""
    Write-Host "  Or manual installation:" -ForegroundColor Yellow
    Write-Host "  1. Open WSL2 terminal" -ForegroundColor White
    Write-Host "  2. Run: curl -fsSL https://get.docker.com -o get-docker.sh" -ForegroundColor White
    Write-Host "  3. Run: sh get-docker.sh" -ForegroundColor White
    Write-Host "  4. Run: sudo service docker start" -ForegroundColor White
    Write-Host "  5. Add your user to docker group: sudo usermod -aG docker `$USER" -ForegroundColor White
    Write-Host "  6. Restart WSL2 or log out and back in" -ForegroundColor White
    Write-Host "  7. Test: wsl docker ps" -ForegroundColor White
    Write-Host ""
    Write-Host "  Note: The 'act' tool should automatically detect WSL2 Docker." -ForegroundColor Yellow
    Write-Host ""
}

Write-Host "Option 2: Install Docker Desktop (Full GUI application)" -ForegroundColor Cyan
Write-Host "  1. Download Docker Desktop from:" -ForegroundColor White
Write-Host "     https://www.docker.com/products/docker-desktop" -ForegroundColor Green
Write-Host "  2. Run the installer" -ForegroundColor White
Write-Host "  3. Follow the installation wizard" -ForegroundColor White
Write-Host "  4. Restart your computer if prompted" -ForegroundColor White
Write-Host "  5. Start Docker Desktop and wait for it to be ready" -ForegroundColor White
Write-Host "  6. Run this script again to verify installation" -ForegroundColor White
Write-Host ""

if (-not $wslAvailable) {
    Write-Host "Option 3: Install WSL2 first, then Docker Engine" -ForegroundColor Cyan
    Write-Host "  1. Install WSL2: wsl --install" -ForegroundColor White
    Write-Host "  2. Restart your computer" -ForegroundColor White
    Write-Host "  3. Follow Option 1 above to install Docker Engine in WSL2" -ForegroundColor White
    Write-Host ""
}

Write-Host "Note: Docker is only needed if you want to test GitHub Actions locally with 'act' tool." -ForegroundColor Yellow
Write-Host "If you only need to run workflows on GitHub, you don't need Docker." -ForegroundColor Yellow
Write-Host ""

exit 1

