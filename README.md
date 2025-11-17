
---

# Linux Installer

**Branch:** `Linux`  
**File:** `install-glpi-agent.sh`

This is a universal, interactive Linux installer for the GLPI Inventory Agent. It supports:

- Debian / Ubuntu  
- Rocky Linux / AlmaLinux / CentOS / RHEL  
- Generic Linux (tar.gz fallback)

### Features

- Prompts for GLPI server URL  
- Prompts for TAG  
- Prompts for agent version  
- Auto-detects Linux distribution family  
- Downloads the proper package (`.deb`, `.rpm`, or `.tar.gz`)  
- Creates `/etc/glpi-agent/conf.d/` configuration  
- Creates systemd service if missing  
- Starts and enables the service  
- Forces an initial inventory

### Running the Linux installer

Option A: Run directly in one line:

curl -s https://raw.githubusercontent.com/SDenbow/glpi-tools/Linux/install-glpi-agent.sh | sudo bash


Option B: Download manually:

curl -O https://raw.githubusercontent.com/SDenbow/glpi-tools/Linux/install-glpi-agent.sh
chmod +x install-glpi-agent.sh
sudo ./install-glpi-agent.sh
