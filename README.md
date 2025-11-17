# Windows Installer

**Branch:** `Windows`  
**File:** `install-glpi-agent.ps1`

This PowerShell-based installer sets up the GLPI Inventory Agent on Windows systems.  
It supports:

- Windows 10 / 11  
- Windows Server 2016 / 2019 / 2022  
- Domain-joined or standalone machines  
- 64-bit GLPI Agent MSI installers  

## Features

- Detects most recent GLPI Agent MSI version  
- Prompts for GLPI server URL  
- Prompts for TAG  
- Downloads the MSI installer  
- Installs silently using `msiexec`  
- Creates/updates the configuration file  
- Forces an immediate inventory after installation  

---

## Running the Windows installer

### Option A – Run directly from PowerShell (one-liner)

Run PowerShell **as Administrator**, then paste:

    irm https://raw.githubusercontent.com/SDenbow/glpi-tools/Windows/install-glpi-agent.ps1 | iex

### Option B – Download and run manually

    Invoke-WebRequest -Uri https://raw.githubusercontent.com/SDenbow/glpi-tools/Windows/install-glpi-agent.ps1 -OutFile install-glpi-agent.ps1
    powershell.exe -ExecutionPolicy Bypass -File install-glpi-agent.ps1

---

## Silent mode (no prompts)

This installs using default values inside the script:

    powershell.exe -ExecutionPolicy Bypass -File install-glpi-agent.ps1 -Silent

---

## Uninstalling the GLPI Agent

    Get-WmiObject Win32_Product | Where-Object { $_.Name -like "GLPI*Agent*" } | ForEach-Object { $_.Uninstall() }

---

## Logs

Installer logs are written to:

    C:\ProgramData\GLPI-Agent\logs\install.log

Inventory logs are here:

    C:\ProgramData\GLPI-Agent\logs\inventory.log
