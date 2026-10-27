
#!/usr/bin/env bash
# ============================================================
# GLPI Agent Interactive Auto-Installer for Linux
#
# Supports:
#   - Debian / Ubuntu
#   - Rocky / AlmaLinux / RHEL / CentOS
#
# Features:
#   - Interactive configuration (including curl | bash)
#   - Server URL and tag validation
#   - Configurable agent version
#   - Package download validation
#   - Systemd service management
#   - Forced inventory after installation
#
# License: GNU GPL v3.0 or later
# ============================================================

set -Eeuo pipefail

DEFAULT_VERSION="1.15"
CONFIG_DIR="/etc/glpi-agent"
WORK_DIR="$(mktemp -d /tmp/glpi-install.XXXXXX)"

cleanup() {
    rm -rf "$WORK_DIR"
}

trap cleanup EXIT

error() {
    echo "ERROR: $*" >&2
    exit 1
}

info() {
    echo "[INFO] $*"
}

# ------------------------------------------------------------
# Require root privileges
# ------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
    error "Run this installer as root using sudo."
fi

# ------------------------------------------------------------
# Interactive prompts
# Read from terminal, not piped stdin
# ------------------------------------------------------------
if [[ ! -r /dev/tty ]]; then
    error "Interactive terminal required."
fi

prompt() {
    local variable="$1"
    local message="$2"
    local answer

    read -r -p "$message" answer < /dev/tty ||
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

[[ "$SERVER_URL" =~ ^https?:// ]] ||
    error "Server URL must begin with http:// or https://"

prompt TAG_VALUE \
    "Enter TAG for this machine (e.g. Office, Home): "

[[ -n "$TAG_VALUE" ]] ||
    error "TAG is required."

prompt VERSION \
    "Enter GLPI Agent version [${DEFAULT_VERSION}]: "

VERSION="${VERSION:-$DEFAULT_VERSION}"

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] ||
    error "Invalid version format."

# Prevent malformed configuration values
[[ "$SERVER_URL" != *$'\n'* && "$SERVER_URL" != *$'\r'* ]] ||
    error "Invalid server URL."

[[ "$TAG_VALUE" != *$'\n'* && "$TAG_VALUE" != *$'\r'* ]] ||
    error "Invalid TAG."

echo ""
echo "------------------------------------------------------------"
echo "Installation Configuration"
echo "------------------------------------------------------------"
echo "Server URL : $SERVER_URL"
echo "TAG        : $TAG_VALUE"
echo "Version    : $VERSION"
echo "------------------------------------------------------------"
echo ""

# ------------------------------------------------------------
# Detect operating system
# ------------------------------------------------------------
[[ -f /etc/os-release ]] ||
    error "Cannot identify operating system."

source /etc/os-release

OS_FAMILY=""

case "${ID,,}" in
    ubuntu|debian)
        OS_FAMILY="debian"
        ;;
    rocky|almalinux|rhel|centos|ol|fedora)
        OS_FAMILY="rhel"
        ;;
    *)
        case " ${ID_LIKE:-} " in
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
    error "Unsupported Linux distribution: ${ID}"

info "Detected OS: ${PRETTY_NAME:-$ID}"
info "OS family: $OS_FAMILY"

ARCH="$(uname -m)"

# ------------------------------------------------------------
# Install dependencies and download package
# ------------------------------------------------------------
RELEASE_URL="https://github.com/glpi-project/glpi-agent/releases/download/${VERSION}"

download_package() {
    local url="$1"
    local output="$2"

    info "Downloading: $url"

    curl --fail --location --show-error \
         --retry 3 \
         --connect-timeout 20 \
         --output "$output" \
         "$url" ||
        error "Package download failed."

    [[ -s "$output" ]] ||
        error "Downloaded package is empty."
}

if [[ "$OS_FAMILY" == "debian" ]]; then

    info "Installing dependencies..."

    apt-get update
    DEBIAN_FRONTEND=noninteractive \
        apt-get install -y \
        curl perl dmidecode ca-certificates

    PKG="glpi-agent_${VERSION}-1_all.deb"
    PKG_PATH="${WORK_DIR}/${PKG}"

    download_package \
        "${RELEASE_URL}/${PKG}" \
        "$PKG_PATH"

    info "Validating Debian package..."

    dpkg-deb --info "$PKG_PATH" >/dev/null ||
        error "Invalid Debian package."

    info "Installing GLPI Agent..."

    # apt resolves dependencies when installing a local .deb
    DEBIAN_FRONTEND=noninteractive \
        apt-get install -y "$PKG_PATH"

elif [[ "$OS_FAMILY" == "rhel" ]]; then

    [[ "$ARCH" == "x86_64" ]] ||
        error "This RPM installer currently supports x86_64 only."

    info "Installing dependencies..."

    if command -v dnf >/dev/null 2>&1; then
        PKG_MANAGER="dnf"
    elif command -v yum >/dev/null 2>&1; then
        PKG_MANAGER="yum"
    else
        error "Neither dnf nor yum is available."
    fi

    "$PKG_MANAGER" install -y \
        curl perl dmidecode ca-certificates

    PKG="glpi-agent-${VERSION}-1.x86_64.rpm"
    PKG_PATH="${WORK_DIR}/${PKG}"

    download_package \
        "${RELEASE_URL}/${PKG}" \
        "$PKG_PATH"

    info "Validating RPM package..."

    rpm -K "$PKG_PATH" ||
        error "RPM package validation failed."

    info "Installing GLPI Agent..."

    "$PKG_MANAGER" install -y "$PKG_PATH"

fi

# ------------------------------------------------------------
# Locate installed agent
# ------------------------------------------------------------
AGENT_BIN="$(command -v glpi-agent || true)"

[[ -n "$AGENT_BIN" && -x "$AGENT_BIN" ]] ||
    error "GLPI Agent binary not found after installation."

info "Agent binary: $AGENT_BIN"

# ------------------------------------------------------------
# Configure GLPI Agent
# ------------------------------------------------------------
info "Writing configuration files..."

mkdir -p "${CONFIG_DIR}/conf.d"

# Remove files managed by this installer, if present.
rm -f \
    "${CONFIG_DIR}/conf.d/00-server.cfg" \
    "${CONFIG_DIR}/conf.d/10-tag.cfg"

cat > "${CONFIG_DIR}/conf.d/00-server.cfg" <<EOF
# Managed by GLPI Agent Auto-Installer
server=${SERVER_URL}
tasks=inventory
EOF

cat > "${CONFIG_DIR}/conf.d/10-tag.cfg" <<EOF
# Managed by GLPI Agent Auto-Installer
tag=${TAG_VALUE}
EOF

chmod 644 \
    "${CONFIG_DIR}/conf.d/00-server.cfg" \
    "${CONFIG_DIR}/conf.d/10-tag.cfg"

# ------------------------------------------------------------
# Ensure systemd service exists
# ------------------------------------------------------------
if command -v systemctl >/dev/null 2>&1; then

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
ExecStart=${AGENT_BIN} --conf-file ${CONFIG_DIR}/agent.cfg
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    fi

    info "Enabling and restarting GLPI Agent service..."

    systemctl daemon-reload
    systemctl enable glpi-agent
    systemctl restart glpi-agent

else
    info "systemd unavailable; skipping service configuration."
fi

# ------------------------------------------------------------
# Force immediate inventory
# ------------------------------------------------------------
echo ""
echo "============================================================"
echo "              FORCING INITIAL INVENTORY"
echo "============================================================"
echo ""

info "Sending inventory to: $SERVER_URL"
info "Using TAG: $TAG_VALUE"

# Explicit parameters ensure this initial run uses
# the settings supplied during installation.
if "$AGENT_BIN" \
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
    echo "Version    : $VERSION"
    echo "Inventory  : Command completed successfully"
    echo ""
    echo "Verify this machine appears in GLPI."
    echo ""

else
    echo ""
    echo "WARNING: Agent installed, but inventory command failed."
    echo ""
    echo "Check connectivity and agent logs."
    echo "You can retry using:"
    echo ""
    echo "  glpi-agent --force"
    echo ""

    exit 1
fi
