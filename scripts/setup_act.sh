#!/bin/bash
# Setup act tool for local GitHub Actions debugging
# Usage: bash scripts/setup_act.sh

set -e

echo "=========================================="
echo "Setting up act for local GitHub Actions debugging"
echo "=========================================="
echo ""

# Check if act is already installed
if command -v act &> /dev/null; then
    echo "act is already installed"
    act --version
    exit 0
fi

# Detect OS
OS="$(uname -s)"
case "${OS}" in
    Linux*)
        echo "Installing act on Linux..."
        curl https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash
        ;;
    Darwin*)
        echo "Installing act on macOS..."
        if command -v brew &> /dev/null; then
            brew install nektos/tap/act
        else
            echo "Error: Homebrew is required for macOS installation"
            echo "Please install Homebrew first: https://brew.sh"
            exit 1
        fi
        ;;
    *)
        echo "Error: Unsupported OS: $OS"
        echo "Please install act manually from: https://github.com/nektos/act/releases"
        exit 1
        ;;
esac

echo ""
echo "act installed successfully!"
act --version


