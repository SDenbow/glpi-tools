<# 
    Install-GlpiAgent-GUI.ps1
    Simple GUI for installing the GLPI Agent.

    - Field for TAG
    - Optional field for Version (defaults to 1.15)
    - Field for GLPI server URL
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Install-GlpiAgent {
    param(
        [string]$Tag,
        [string]$Version   = "1.15",
        [string]$ServerUrl = "https://your-glpi-server.example.com/front/inventory.php"
    )

    if ([string]::IsNullOrWhiteSpace($Tag)) {
        [System.Windows.Forms.MessageBox]::Show(
            "TAG is required.","Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        return
    }

    # Admin check
    $principal = New-Object Security.Principal.WindowsPrincipal(
        [Security.Principal.WindowsIdentity]::GetCurrent()
    )
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        [System.Windows.Forms.MessageBox]::Show(
            "Please run this script as Administrator.","Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        return
    }

    # MSI download URL
    $msiUrl = "https://github.com/glpi-project/glpi-agent/releases/download/$Version/GLPI-Agent-$Version-x64.msi"
    $tempFile = Join-Path $env:TEMP "GLPI-Agent-$Version-x64.msi"

    try {
        (New-Object Net.WebClient).DownloadFile($msiUrl, $tempFile)
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Failed to download GLPI Agent MSI.`n$_","Download Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        return
    }

    # Install silently
    $installArgs = "/i `"$tempFile`" /quiet /norestart SERVER=$ServerUrl TAG=$Tag"
    $process = Start-Process "msiexec.exe" -ArgumentList $installArgs -Wait -PassThru

    if ($process.ExitCode -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "GLPI Agent installed successfully.","Success",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    }
    else {
        [System.Windows.Forms.MessageBox]::Show(
            "Installation failed with exit code: $($process.ExitCode)","Install Failed",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
}

# -------------------------------
# GUI SETUP
# -------------------------------

$form              = New-Object System.Windows.Forms.Form
$form.Text         = "GLPI Agent Installer"
$form.Size         = New-Object System.Drawing.Size(420,270)
$form.StartPosition= "CenterScreen"

# TAG Label + Box
$tagLabel          = New-Object System.Windows.Forms.Label
$tagLabel.Text     = "TAG:"
$tagLabel.Location = New-Object System.Drawing.Point(20,20)
$tagLabel.AutoSize = $true

$tagBox            = New-Object System.Windows.Forms.TextBox
$tagBox.Location   = New-Object System.Drawing.Point(120,20)
$tagBox.Size       = New-Object System.Drawing.Size(250,20)
$tagBox.Text       = ""

# Version Label + Box
$versionLabel          = New-Object System.Windows.Forms.Label
$versionLabel.Text     = "Version:"
$versionLabel.Location = New-Object System.Drawing.Point(20,60)
$versionLabel.AutoSize = $true

$versionBox            = New-Object System.Windows.Forms.TextBox
$versionBox.Location   = New-Object System.Drawing.Point(120,60)
$versionBox.Size       = New-Object System.Drawing.Size(250,20)
$versionBox.Text       = "1.15"

# Server URL Label + Box
$urlLabel          = New-Object System.Windows.Forms.Label
$urlLabel.Text     = "Server URL:"
$urlLabel.Location = New-Object System.Drawing.Point(20,100)
$urlLabel.AutoSize = $true

$urlBox            = New-Object System.Windows.Forms.TextBox
$urlBox.Location   = New-Object System.Drawing.Point(120,100)
$urlBox.Size       = New-Object System.Drawing.Size(250,20)
$urlBox.Text       = "https://your-glpi-server.example.com/front/inventory.php"

# Install Button
$installButton            = New-Object System.Windows.Forms.Button
$installButton.Text       = "Install Agent"
$installButton.Location   = New-Object System.Drawing.Point(120,150)
$installButton.Add_Click({
    Install-GlpiAgent -Tag $tagBox.Text -Version $versionBox.Text -ServerUrl $urlBox.Text
})

# Add controls to form
$form.Controls.AddRange(@(
    $tagLabel, $tagBox,
    $versionLabel, $versionBox,
    $urlLabel, $urlBox,
    $installButton
))

$form.ShowDialog()
