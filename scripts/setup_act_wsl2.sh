#!/bin/bash
# Setup act tool in WSL2
# Usage: wsl bash scripts/setup_act_wsl2.sh
# Or: wsl -d Ubuntu-24.04 bash scripts/setup_act_wsl2.sh

set -e

echo "=========================================="
echo "Setting up act tool in WSL2"
echo "=========================================="
echo ""

# Check if act is already installed
if command -v act &> /dev/null; then
    echo "act is already installed"
    act --version
    exit 0
fi

echo "Installing act tool..."
echo ""

# Method 1: Try using the official install script
echo "Attempting to install using official script..."
if curl -s https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash; then
    echo ""
    echo "act installed successfully!"
    act --version
    exit 0
fi

# Method 2: Download binary directly (if script fails)
echo ""
echo "Official script failed, trying direct download..."
echo ""

# Detect architecture
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)
        ACT_ARCH="x86_64"
        ;;
    aarch64|arm64)
        ACT_ARCH="arm64"
        ;;
    *)
        echo "Error: Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

# Get latest version
echo "Fetching latest act version..."
LATEST_VERSION=$(curl -s https://api.github.com/repos/nektos/act/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

if [ -z "$LATEST_VERSION" ]; then
    echo "Error: Could not determine latest version"
    exit 1
fi

echo "Latest version: $LATEST_VERSION"
echo ""

# Create local bin directory if it doesn't exist
mkdir -p ~/.local/bin

# Download act binary
ACT_URL="https://github.com/nektos/act/releases/download/${LATEST_VERSION}/act_Linux_${ACT_ARCH}.tar.gz"
echo "Downloading act from: $ACT_URL"
curl -L -o /tmp/act.tar.gz "$ACT_URL"

# Extract
echo "Extracting..."
tar -xzf /tmp/act.tar.gz -C /tmp

# Install to local bin
echo "Installing to ~/.local/bin..."
mv /tmp/act ~/.local/bin/act
chmod +x ~/.local/bin/act

# Add to PATH if not already there
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    echo ""
    echo "Adding ~/.local/bin to PATH..."
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
    export PATH="$HOME/.local/bin:$PATH"
    echo "Note: You may need to run 'source ~/.bashrc' or restart your terminal"
fi

# Cleanup
rm -f /tmp/act.tar.gz

echo ""
echo "=========================================="
echo "act installed successfully!"
echo "=========================================="
echo ""
act --version
echo ""
echo "Test act with: act -l"
echo ""

