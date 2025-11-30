#!/bin/bash
# Setup Docker Engine in WSL2
# Usage: wsl bash scripts/setup_docker_wsl2.sh
# Or: wsl -d Ubuntu-24.04 bash scripts/setup_docker_wsl2.sh

set -e

echo "=========================================="
echo "Setting up Docker Engine in WSL2"
echo "=========================================="
echo ""

# Check if Docker is already installed
if command -v docker &> /dev/null; then
    echo "Docker is already installed"
    docker --version
    
    # Check if Docker daemon is running
    echo ""
    echo "Checking if Docker daemon is running..."
    if sudo docker ps &> /dev/null; then
        echo "Docker daemon is running"
        
        # Check if current user is in docker group
        if groups | grep -q docker; then
            echo "Current user is in docker group"
            echo ""
            echo "Testing Docker without sudo..."
            if docker ps &> /dev/null; then
                echo "Docker is working correctly!"
                exit 0
            else
                echo "Warning: Docker requires sudo. Adding user to docker group..."
            fi
        else
            echo "Current user is not in docker group. Adding user to docker group..."
        fi
        
        # Add user to docker group
        sudo usermod -aG docker $USER
        echo ""
        echo "User added to docker group. Please log out and log back in, or run:"
        echo "  newgrp docker"
        echo ""
        echo "Then test Docker with: docker ps"
        exit 0
    else
        echo "Docker is installed but daemon is not running"
        echo "Starting Docker daemon..."
        sudo service docker start
        if [ $? -eq 0 ]; then
            echo "Docker daemon started successfully"
            echo "Testing Docker..."
            if sudo docker ps &> /dev/null; then
                echo "Docker is working!"
                
                # Add user to docker group if not already
                if ! groups | grep -q docker; then
                    sudo usermod -aG docker $USER
                    echo "User added to docker group. Please log out and log back in."
                fi
                exit 0
            fi
        else
            echo "Failed to start Docker daemon"
            exit 1
        fi
    fi
fi

echo "Docker is not installed. Installing Docker Engine..."
echo ""

# Update package index
echo "Updating package index..."
sudo apt-get update

# Install prerequisites
echo "Installing prerequisites..."
sudo apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

# Add Docker's official GPG key
echo "Adding Docker's official GPG key..."
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Set up the repository
echo "Setting up Docker repository..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine
echo "Installing Docker Engine..."
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Start Docker service
echo "Starting Docker service..."
sudo service docker start

# Enable Docker to start on boot (optional)
echo "Enabling Docker to start on boot..."
sudo systemctl enable docker 2>/dev/null || echo "Note: systemd may not be available in WSL2"

# Add current user to docker group
echo "Adding current user to docker group..."
sudo usermod -aG docker $USER

echo ""
echo "=========================================="
echo "Docker Engine installed successfully!"
echo "=========================================="
echo ""
echo "Important: You need to log out and log back in for group changes to take effect."
echo "Or you can run: newgrp docker"
echo ""
echo "Test Docker with:"
echo "  docker ps"
echo ""
echo "If you're running this from Windows PowerShell, you can test with:"
echo "  wsl docker ps"
echo ""





