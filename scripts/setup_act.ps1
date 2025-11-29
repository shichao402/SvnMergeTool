# Setup act tool for local GitHub Actions debugging
# Usage: powershell -ExecutionPolicy Bypass -File scripts\setup_act.ps1

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Setting up act for local GitHub Actions debugging" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Check if act is already installed
$actInstalled = Get-Command act -ErrorAction SilentlyContinue

if ($actInstalled) {
    Write-Host "act is already installed" -ForegroundColor Green
    act --version
    exit 0
}

# Check for Scoop
$scoopInstalled = Get-Command scoop -ErrorAction SilentlyContinue

if ($scoopInstalled) {
    Write-Host "Installing act using Scoop..." -ForegroundColor Yellow
    scoop install act
} else {
    Write-Host "Scoop is not installed. Installing Scoop first..." -ForegroundColor Yellow
    Write-Host "Please run:" -ForegroundColor Cyan
    Write-Host "  Set-ExecutionPolicy RemoteSigned -Scope CurrentUser" -ForegroundColor White
    Write-Host "  irm get.scoop.sh | iex" -ForegroundColor White
    Write-Host ""
    Write-Host "Or download act manually from:" -ForegroundColor Cyan
    Write-Host "  https://github.com/nektos/act/releases" -ForegroundColor White
    exit 1
}

Write-Host ""
Write-Host "act installed successfully!" -ForegroundColor Green
act --version


