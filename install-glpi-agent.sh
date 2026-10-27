
#!/usr/bin/env bash
# ============================================================
# GLPI Agent Interactive Auto-Installer for Linux
#
# Supports:
#   Debian / Ubuntu
#   Rocky / AlmaLinux / RHEL / CentOS
#
# Features:
#   - Works with curl | sudo bash
#   - Interactive server, tag, and version prompts
#   - Safe OS detection without variable collisions
#   - Validated package downloads
#   - Dependency-aware package installation
#   - Persistent GLPI Agent configuration
#   - Systemd service management
#   - Forced initial inventory
#
# License: GNU GPL v3.0 or later
# ============================================================

set -Eeuo pipefail

DEFAULT_AGENT_VERSION="1.15"
CONFIG_DIR="/etc/glpi-agent"
CONFIG_FILE="${CONFIG_DIR}/agent.cfg"

WORK_DIR=""

cleanup() {
    if [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then
        rm -rf -- "$WORK_DIR"
    fi
}

trap cleanup EXIT

error() {
    echo "[ERROR] $*" >&2
    exit 1
}

info() {
    echo "[INFO] $*"
}

warn() {
    echo "[WARNING] $*" >&2
}

# ------------------------------------------------------------
# Require root and interactive terminal
# ------------------------------------------------------------
[[ $EUID -eq 0 ]] ||
    error "Run this installer with sudo or as root."

[[ -r /dev/tty ]] ||
    error "An interactive terminal is required."

# ------------------------------------------------------------
# Prompt helper
# Read from /dev/tty instead of piped stdin
# ------------------------------------------------------------
prompt() {
    local variable="$1"
    local message="$2"
    local answer

    IFS= read -r -p "$message" answer < /dev/tty ||
        error "Unable to read terminal input."

    printf -v "$variable" '%s' "$answer"
}

echo "============================================================"
echo "             GLPI Agent Interactive Installer"
echo "============================================================"
echo ""

prompt SERVER_URL \
    "Enter GLPI inventory server URL: "

[[ -n "$SERVER_URL" ]] ||
    error "Server URL is required."

[[ "$SERVER_URL" =~ ^https?://[^[:space:]]+$ ]] ||
    error "Server URL must be a valid HTTP/HTTPS URL without spaces."

prompt TAG_VALUE \
    "Enter TAG for this machine (e.g. LA, ATL, Home): "

[[ -n "$TAG_VALUE" ]] ||
    error "TAG is required."

[[ "$TAG_VALUE" =~ ^[A-Za-z0-9_.-]+$ ]] ||
    error "TAG may contain letters, numbers, underscores, dots, or hyphens."

prompt AGENT_VERSION \
    "Enter GLPI Agent version [${DEFAULT_AGENT_VERSION}]: "

AGENT_VERSION="${AGENT_VERSION:-$DEFAULT_AGENT_VERSION}"

[[ "$AGENT_VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] ||
    error "Invalid agent version format."

echo ""
echo "------------------------------------------------------------"
echo "Installation Configuration"
echo "------------------------------------------------------------"
echo "Server URL : $SERVER_URL"
echo "TAG        : $TAG_VALUE"
echo "Version    : $AGENT_VERSION"
echo "------------------------------------------------------------"
echo ""

# ------------------------------------------------------------
# Detect operating system safely
#
# /etc/os-release defines VERSION, so do not source it
# into the main script environment.
# ------------------------------------------------------------
[[ -f /etc/os-release ]] ||
    error "Cannot identify the operating system."

OS_ID="$(
    . /etc/os-release
    printf '%s' "${ID:-}"
)"

OS_ID_LIKE="$(
    . /etc/os-release
    printf '%s' "${ID_LIKE:-}"
)"

OS_PRETTY_NAME="$(
    . /etc/os-release
    printf '%s' "${PRETTY_NAME:-Unknown Linux}"
)"

OS_FAMILY=""

case "${OS_ID,,}" in
    ubuntu|debian)
        OS_FAMILY="debian"
        ;;
    rocky|almalinux|rhel|centos|ol|fedora)
        OS_FAMILY="rhel"
        ;;
    *)
        case " ${OS_ID_LIKE,,} " in
            *debian*|*ubuntu*)
                OS_FAMILY="debian"
                ;;
            *rhel*|*fedora*|*centos*)
                OS_FAMILY="rhel"
                ;;
        esac
        ;;
esac

[[ -n "$OS_FAMILY" ]] ||
    error "Unsupported Linux distribution: $OS_ID"

info "Detected OS: $OS_PRETTY_NAME"
info "OS family: $OS_FAMILY"

# ------------------------------------------------------------
# Check required commands
# ------------------------------------------------------------
command -v curl >/dev/null 2>&1 ||
    error "curl is required to download the GLPI Agent."

command -v systemctl >/dev/null 2>&1 ||
    error "This installer requires systemd."

# ------------------------------------------------------------
# Prepare temporary working directory
# ------------------------------------------------------------
WORK_DIR="$(mktemp -d /tmp/glpi-install.XXXXXX)"

RELEASE_URL="https://github.com/glpi-project/glpi-agent/releases/download/${AGENT_VERSION}"

download_package() {
    local url="$1"
    local output="$2"

    info "Downloading: $url"

    curl \
        --fail \
        --location \
        --show-error \
        --retry 3 \
        --connect-timeout 20 \
        --output "$output" \
        "$url" ||
        error "Failed to download GLPI Agent package."

    [[ -s "$output" ]] ||
        error "Downloaded package is empty."
}

# ------------------------------------------------------------
# Debian / Ubuntu installation
# ------------------------------------------------------------
if [[ "$OS_FAMILY" == "debian" ]]; then

    info "Updating package indexes..."
    apt-get update

    info "Installing prerequisites..."

    DEBIAN_FRONTEND=noninteractive \
        apt-get install -y \
        curl \
        perl \
        dmidecode \
        ca-certificates

    PKG="glpi-agent_${AGENT_VERSION}-1_all.deb"
    PKG_PATH="${WORK_DIR}/${PKG}"

    download_package \
        "${RELEASE_URL}/${PKG}" \
        "$PKG_PATH"

    info "Validating Debian package..."

    dpkg-deb --info "$PKG_PATH" >/dev/null ||
        error "Downloaded file is not a valid Debian package."

    info "Installing GLPI Agent..."

    DEBIAN_FRONTEND=noninteractive \
        apt-get install -y "$PKG_PATH" ||
        error "GLPI Agent package installation failed."

# ------------------------------------------------------------
# RHEL / Rocky / AlmaLinux / CentOS installation
# ------------------------------------------------------------
elif [[ "$OS_FAMILY" == "rhel" ]]; then

    ARCH="$(uname -m)"

    [[ "$ARCH" == "x86_64" ]] ||
        error "Unsupported RPM architecture: $ARCH"

    if command -v dnf >/dev/null 2>&1; then
        PKG_MANAGER="dnf"
    elif command -v yum >/dev/null 2>&1; then
        PKG_MANAGER="yum"
    else
        error "Neither dnf nor yum is available."
    fi

    info "Installing prerequisites..."

    "$PKG_MANAGER" install -y \
        curl \
        perl \
        dmidecode \
        ca-certificates

    PKG="glpi-agent-${AGENT_VERSION}-1.x86_64.rpm"
    PKG_PATH="${WORK_DIR}/${PKG}"

    download_package \
        "${RELEASE_URL}/${PKG}" \
        "$PKG_PATH"

    info "Validating RPM package..."

    rpm -K "$PKG_PATH" ||
        error "RPM package validation failed."

    info "Installing GLPI Agent..."

    "$PKG_MANAGER" install -y "$PKG_PATH" ||
        error "GLPI Agent package installation failed."

fi

# ------------------------------------------------------------
# Verify agent installation
# ------------------------------------------------------------
AGENT_BIN="$(command -v glpi-agent || true)"

[[ -n "$AGENT_BIN" && -x "$AGENT_BIN" ]] ||
    error "GLPI Agent executable not found after installation."

info "Agent binary: $AGENT_BIN"

info "Checking installed agent..."

"$AGENT_BIN" --version ||
    error "Installed GLPI Agent failed its version check."

# ------------------------------------------------------------
# Configure GLPI Agent
#
# Use the primary configuration file so configuration
# does not depend on conf.d loading behavior.
# ------------------------------------------------------------
info "Configuring GLPI Agent..."

mkdir -p "$CONFIG_DIR"

# Preserve an existing configuration before changing it.
if [[ -f "$CONFIG_FILE" ]]; then
    BACKUP_FILE="${CONFIG_FILE}.backup.$(date +%Y%m%d-%H%M%S)"
    cp -p "$CONFIG_FILE" "$BACKUP_FILE"
    info "Existing configuration backed up to: $BACKUP_FILE"
fi

# Remove previously generated configuration fragments
# from older versions of this installer.
rm -f \
    "${CONFIG_DIR}/conf.d/00-server.cfg" \
    "${CONFIG_DIR}/conf.d/10-tag.cfg"

# Update only the settings managed by this installer.
# Preserve unrelated existing configuration options.
touch "$CONFIG_FILE"

sed -i \
    -e '/^[[:space:]]*server[[:space:]]*=/d' \
    -e '/^[[:space:]]*tag[[:space:]]*=/d' \
    -e '/^[[:space:]]*tasks[[:space:]]*=/d' \
    "$CONFIG_FILE"

cat >> "$CONFIG_FILE" <<EOF

# GLPI Agent Auto-Installer settings
server=${SERVER_URL}
tag=${TAG_VALUE}
tasks=inventory
EOF

chmod 644 "$CONFIG_FILE"

info "Configuration saved to: $CONFIG_FILE"

# ------------------------------------------------------------
# Configure systemd service
# ------------------------------------------------------------
info "Checking systemd service..."

if ! systemctl list-unit-files glpi-agent.service \
    --no-legend 2>/dev/null |
    grep -q '^glpi-agent.service'; then

    info "Creating GLPI Agent systemd service..."

    cat > /etc/systemd/system/glpi-agent.service <<EOF
[Unit]
Description=GLPI Inventory Agent
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
ExecStart=${AGENT_BIN} --conf-file ${CONFIG_FILE}
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

fi

info "Reloading systemd..."
systemctl daemon-reload

info "Enabling GLPI Agent service..."
systemctl enable glpi-agent ||
    error "Unable to enable GLPI Agent service."

info "Restarting GLPI Agent service..."
systemctl restart glpi-agent ||
    error "Unable to restart GLPI Agent service."

if systemctl is-active --quiet glpi-agent; then
    info "GLPI Agent service is active."
else
    warn "GLPI Agent service is not currently active."
    warn "Check: journalctl -u glpi-agent -n 50"
fi

# ------------------------------------------------------------
# Force initial inventory
# ------------------------------------------------------------
echo ""
echo "============================================================"
echo "              FORCING INITIAL INVENTORY"
echo "============================================================"
echo ""

info "Server: $SERVER_URL"
info "TAG: $TAG_VALUE"

# Explicit arguments ensure the initial inventory uses
# the configuration selected during installation.
if "$AGENT_BIN" \
    --conf-file "$CONFIG_FILE" \
    --server "$SERVER_URL" \
    --tag "$TAG_VALUE" \
    --tasks inventory \
    --force; then

    echo ""
    echo "============================================================"
    echo "            GLPI AGENT INSTALLATION COMPLETE"
    echo "============================================================"
    echo ""
    echo "Server URL : $SERVER_URL"
    echo "TAG        : $TAG_VALUE"
    echo "Version    : $AGENT_VERSION"
    echo "Inventory  : Command completed successfully"
    echo ""
    echo "Verify the machine appears in GLPI."
    echo ""

else
    warn "GLPI Agent installed, but initial inventory failed."
    warn "Review the output above and check connectivity."
    warn "Retry using: glpi-agent --force"
    exit 1
fi
