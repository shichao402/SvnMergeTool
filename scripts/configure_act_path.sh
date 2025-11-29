#!/bin/bash
# Configure PATH for act in WSL2
# Usage: wsl bash scripts/configure_act_path.sh

if ! grep -q '\.local/bin' ~/.bashrc; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
    echo "PATH configured in ~/.bashrc"
else
    echo "PATH already configured in ~/.bashrc"
fi

export PATH="$HOME/.local/bin:$PATH"
echo "Current PATH includes ~/.local/bin"

