#!/usr/bin/env bash
# ============================================================
# GLPI Agent Interactive Auto-Installer for Linux
# Supports: Ubuntu/Debian, Rocky/Alma/CentOS/RHEL, generic
#
# License: GNU GPL v3.0 or later
# (Adjust this header if you decide on a different license.)
# ============================================================

set -e

DEFAULT_VERSION="1.15"

echo "============================================================"
echo "             GLPI Agent Interactive Installer               "
echo "============================================================"
echo ""

# --- Ask for server URL (required, no default) ---
read -r -p "Enter GLPI inventory server URL (e.g. https://glpi.example.com/front/inventory.php): " SERVER_URL
if [ -z "$SERVER_URL" ]; then
  echo "ERROR: Server URL is required. Aborting."
  exit 1
fi

# --- Ask for TAG (required) ---
read -r -p "Enter TAG for this machine (e.g. Office, Home): " TAG_VALUE
if [ -z "$TAG_VALUE" ]; then
  echo "ERROR: TAG is required. Aborting."
  exit 1
fi

# --- Ask for version (optional, default 1.15) ---
read -r -p "Enter GLPI Agent version [${DEFAULT_VERSION}]: " VERSION
VERSION="${VERSION:-$DEFAULT_VERSION}"

echo ""
echo "Using settings:"
echo "  Server URL : $SERVER_URL"
echo "  TAG        : $TAG_VALUE"
echo "  Version    : $VERSION"
echo ""

# --- Detect OS family ---
if [ -f /etc/debian_version ]; then
  OS_FAMILY="debian"
elif [ -f /etc/redhat-release ]; then
  OS_FAMILY="rhel"
else
  OS_FAMILY="generic"
fi

echo "Detected OS family: $OS_FAMILY"
echo ""

# ------------------------------------------------------------
# Debian / Ubuntu
# ------------------------------------------------------------
if [ "$OS_FAMILY" = "debian" ]; then
  echo "[1/6] Installing dependencies..."
  sudo apt update
  sudo apt install -y curl perl dmidecode

  PKG="glpi-agent_${VERSION}-1_all.deb"
  URL="https://github.com/glpi-project/glpi-agent/releases/download/${VERSION}/${PKG}"

  echo "[2/6] Downloading package: $URL"
  cd /tmp
  curl -L -o "$PKG" "$URL"

  echo "[3/6] Validating package..."
  if dpkg-deb -I "$PKG" > /dev/null 2>&1; then
    echo "Package looks valid."
  else
    echo "ERROR: Downloaded file is not a valid .deb package."
    exit 1
  fi

  echo "[4/6] Installing package..."
  sudo dpkg -i "$PKG" || sudo apt -f install -y

# ------------------------------------------------------------
# RedHat / CentOS / Rocky / Alma
# ------------------------------------------------------------
elif [ "$OS_FAMILY" = "rhel" ]; then
  echo "[1/6] Installing dependencies..."
  sudo dnf install -y curl perl dmidecode 2>/dev/null || sudo yum install -y curl perl dmidecode

  PKG="glpi-agent-${VERSION}-1.x86_64.rpm"
  URL="https://github.com/glpi-project/glpi-agent/releases/download/${VERSION}/${PKG}"

  echo "[2/6] Downloading package: $URL"
  cd /tmp
  curl -L -o "$PKG" "$URL"

  echo "[3/6] Validating package..."
  if [ ! -s "$PKG" ] || [ "$(stat -c%s "$PKG")" -lt 5000000 ]; then
    echo "ERROR: Downloaded file is too small — likely a bad download or 404."
    echo "       File size: $(stat -c%s "$PKG") bytes"
    exit 1
  fi

  echo "[4/6] Installing package..."
  sudo rpm -Uvh "$PKG"

# ------------------------------------------------------------
# Generic Linux (fallback via tar.gz)
# ------------------------------------------------------------
else
  echo "[!] Unsupported / unknown distro — using generic tar.gz installer"
  sudo mkdir -p /opt/glpi-agent
  cd /opt/glpi-agent

  TGZ="glpi-agent-${VERSION}.tar.gz"
  URL="https://github.com/glpi-project/glpi-agent/releases/download/${VERSION}/${TGZ}"

  echo "[1/6] Downloading tar.gz..."
  sudo curl -L -o "$TGZ" "$URL"
  sudo tar xvf "$TGZ"
fi

# ------------------------------------------------------------
# Determine agent binary path
# ------------------------------------------------------------
if command -v glpi-agent >/dev/null 2>&1; then
  AGENT_BIN="$(command -v glpi-agent)"
elif [ -x /opt/glpi-agent/glpi-agent ]; then
  AGENT_BIN="/opt/glpi-agent/glpi-agent"
else
  echo "ERROR: Could not find glpi-agent binary after install."
  exit 1
fi

echo ""
echo "[5/6] Writing config files..."

sudo mkdir -p /etc/glpi-agent/conf.d

# Server URL + tasks
sudo tee /etc/glpi-agent/conf.d/00-server.cfg >/dev/null <<EOF
server=${SERVER_URL}
tasks=inventory
EOF

# Tag
sudo tee /etc/glpi-agent/conf.d/10-tag.cfg >/dev/null <<EOF
tag=${TAG_VALUE}
EOF

# ------------------------------------------------------------
# Create systemd service if missing
# ------------------------------------------------------------
if ! systemctl list-unit-files | grep -q "^glpi-agent.service"; then
  echo "[i] No glpi-agent.service unit found — creating one at /etc/systemd/system/glpi-agent.service"
  sudo tee /etc/systemd/system/glpi-agent.service >/dev/null <<EOF
[Unit]
Description=GLPI Agent
After=network-online.target

[Service]
Type=simple
ExecStart=${AGENT_BIN} --conf /etc/glpi-agent
Restart=always

[Install]
WantedBy=multi-user.target
EOF
fi

echo "[6/6] Enabling + starting glpi-agent..."

sudo systemctl daemon-reload
sudo systemctl enable glpi-agent
sudo systemctl restart glpi-agent || true

echo ""
echo "------------------------------------------------------------"
echo "GLPI Agent installed (or updated). Forcing an inventory..."
echo "------------------------------------------------------------"
echo ""

sudo "${AGENT_BIN}" --server "${SERVER_URL}" --task inventory || true

echo ""
echo "Done. Verify this host in GLPI inventory (tag: ${TAG_VALUE})."
echo ""
