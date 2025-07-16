#!/bin/bash

# Function to install PowerShell on Debian-based systems (Ubuntu, Debian, etc.)
install_debian() {
  echo "Installing PowerShell on Debian-based system..."
  sudo apt-get update
  sudo apt-get install -y wget apt-transport-https software-properties-common
  wget -q "https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb" -O packages-microsoft-prod.deb
  sudo dpkg -i packages-microsoft-prod.deb
  rm packages-microsoft-prod.deb
  sudo apt-get update
  sudo apt-get install -y powershell
  echo "PowerShell installed successfully on Debian-based system."
}

# Function to install PowerShell on Red Hat-based systems (Fedora, CentOS, RHEL)
install_redhat() {
  echo "Installing PowerShell on Red Hat-based system..."
    sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
    curl https://packages.microsoft.com/config/rhel/$(grep 'VERSION_ID=' /etc/os-release | cut -d '=' -f2 | tr -d '"')/prod.repo | sudo tee /etc/yum.repos.d/microsoft.repo
    sudo yum install -y powershell
  echo "PowerShell installed successfully on Red Hat-based system."
}

# Function to install PowerShell using a binary archive (for other distributions)
install_generic() {
  echo "Installing PowerShell using binary archive..."
    wget https://github.com/PowerShell/PowerShell/releases/download/v7.5.0/powershell-7.5.0-linux-x64.tar.gz
    sudo mkdir -p /opt/microsoft/powershell/7
    sudo tar zxf powershell-7.5.0-linux-x64.tar.gz -C /opt/microsoft/powershell/7
    sudo ln -s /opt/microsoft/powershell/7/pwsh /usr/bin/pwsh
    rm powershell-7.5.0-linux-x64.tar.gz
  echo "PowerShell installed successfully using binary archive."
}

# Determine the Linux distribution
if [ -f /etc/os-release ]; then
  source /etc/os-release
  if [[ "$ID" == "debian" || "$ID_LIKE" == "debian" ]]; then
    install_debian
  elif [[ "$ID" == "fedora" || "$ID_LIKE" == "fedora" || "$ID" == "centos" || "$ID_LIKE" == "rhel" ]]; then
    install_redhat
  else
    install_generic
  fi
else
  install_generic
fi

echo "Installation complete."