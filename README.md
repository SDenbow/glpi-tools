# glpi-tools
This repository contains cross-platform tools to simplify deployment of the GLPI Inventory Agent for Linux and Windows environments.

Contents
File / Folder	Description
install-glpi-agent.sh	Interactive Linux installer for GLPI Agent (Debian, Ubuntu, Rocky, Alma, RHEL & generic). Prompts for server URL, tag, and version.
windows/GLPI-Agent-Installer.exe (optional)	Interactive Windows GUI installer for GLPI Agent, built from PowerShell. Prompts for server URL and tag.
windows/Install-GlpiAgent-GUI.ps1	PowerShell source for building your own Windows installer EXE.
🐧 Linux Installer (interactive)

The Linux installer supports:

Debian / Ubuntu

RHEL / Rocky / Alma / CentOS

Generic Linux (fallback via tar.gz)

It:

Prompts for GLPI server URL

Prompts for TAG (location / site code)

Downloads the appropriate GLPI Agent package

Creates configuration files

Creates systemd service if missing

Starts + enables the service

Forces an inventory

Usage (direct download)
curl -s https://raw.githubusercontent.com/SDenbow/glpi-tools/Linux/install-glpi-agent.sh | sudo bash


Or clone this repo:

git clone https://github.com/SDenbow/glpi-tools
cd glpi-tools
sudo ./install-glpi-agent.sh

🪟 Windows Installer

The Windows installer is a small GUI-based tool (PowerShell → EXE) that:

Prompts for server URL

Prompts for TAG

Downloads the appropriate GLPI Agent MSI

Installs silently

Starts the agent

Forces an inventory

Using the EXE

Download from:

https://github.com/SDenbow/glpi-tools/tree/Windows/windows


Run as Administrator.

Building Yourself

The EXE is generated using ps2exe.

Install-Module ps2exe -Scope CurrentUser -Force

Invoke-ps2exe `
  -inputFile  Install-GlpiAgent-GUI.ps1 `
  -outputFile GLPI-Agent-Installer.exe `
  -noConsole `
  -requireAdmin

📝 License

This project is licensed under the GNU GPL v3.
