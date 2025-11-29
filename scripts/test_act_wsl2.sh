#!/bin/bash
# Test act tool in WSL2
# Usage: wsl bash scripts/test_act_wsl2.sh

export PATH="$HOME/.local/bin:$PATH"

echo "Testing act tool..."
echo ""

# Check if act is available
if ! command -v act &> /dev/null; then
    echo "Error: act is not in PATH"
    echo "Please add ~/.local/bin to your PATH:"
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
    echo "Or add to ~/.bashrc:"
    echo "  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc"
    exit 1
fi

echo "act version:"
act --version
echo ""

echo "Testing Docker connection..."
if docker ps &> /dev/null; then
    echo "Docker is running"
    echo ""
    echo "Listing workflows:"
    act -l
else
    echo "Error: Docker is not running"
    echo "Please start Docker: sudo service docker start"
    exit 1
fi

