#!/bin/bash
# Setup Docker for Linux/macOS
# Usage: bash scripts/setup_docker.sh

set -e

echo "=========================================="
echo "Setting up Docker"
echo "=========================================="
echo ""

# Check if Docker is already installed and running
if command -v docker &> /dev/null; then
    echo "Docker is already installed"
    docker --version
    
    # Check if Docker daemon is running
    echo ""
    echo "Checking if Docker daemon is running..."
    if docker ps &> /dev/null; then
        echo "Docker daemon is running"
        exit 0
    else
        echo "Docker is installed but daemon is not running"
        echo "Please start Docker and try again"
        echo ""
        echo "On Linux, you may need to:"
        echo "  sudo systemctl start docker"
        echo "  sudo usermod -aG docker $USER"
        echo "  (Then log out and log back in)"
        exit 1
    fi
fi

# Detect OS
OS="$(uname -s)"
case "${OS}" in
    Linux*)
        echo "Installing Docker on Linux..."
        echo ""
        
        # Check if running as root
        if [ "$EUID" -eq 0 ]; then
            echo "Error: Please do not run this script as root"
            echo "The script will use sudo when needed"
            exit 1
        fi
        
        # Check for package manager
        if command -v apt-get &> /dev/null; then
            echo "Using apt-get to install Docker..."
            sudo apt-get update
            sudo apt-get install -y \
                ca-certificates \
                curl \
                gnupg \
                lsb-release
            
            # Add Docker's official GPG key
            sudo mkdir -p /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            
            # Set up the repository
            echo \
              "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
              $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            
            # Install Docker Engine
            sudo apt-get update
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            
        elif command -v yum &> /dev/null; then
            echo "Using yum to install Docker..."
            sudo yum install -y yum-utils
            sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            sudo systemctl start docker
            sudo systemctl enable docker
            
        elif command -v dnf &> /dev/null; then
            echo "Using dnf to install Docker..."
            sudo dnf install -y dnf-plugins-core
            sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
            sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            sudo systemctl start docker
            sudo systemctl enable docker
            
        else
            echo "Error: Unsupported package manager"
            echo "Please install Docker manually from: https://docs.docker.com/get-docker/"
            exit 1
        fi
        
        # Add current user to docker group
        echo ""
        echo "Adding current user to docker group..."
        sudo usermod -aG docker $USER
        echo "User added to docker group. You may need to log out and log back in for this to take effect."
        echo ""
        echo "To test Docker without logging out, you can run:"
        echo "  newgrp docker"
        echo ""
        echo "Docker installed successfully!"
        docker --version
        ;;
        
    Darwin*)
        echo "Installing Docker on macOS..."
        echo ""
        
        if command -v brew &> /dev/null; then
            echo "Using Homebrew to install Docker Desktop..."
            brew install --cask docker
            echo ""
            echo "Docker Desktop installed successfully!"
            echo "Please start Docker Desktop from Applications and wait for it to be ready."
            echo "Then run this script again to verify."
        else
            echo "Error: Homebrew is required for macOS installation"
            echo "Please install Homebrew first: https://brew.sh"
            echo ""
            echo "Or download Docker Desktop manually from:"
            echo "  https://www.docker.com/products/docker-desktop"
            exit 1
        fi
        ;;
        
    *)
        echo "Error: Unsupported OS: $OS"
        echo "Please install Docker manually from: https://www.docker.com/get-started"
        exit 1
        ;;
esac

