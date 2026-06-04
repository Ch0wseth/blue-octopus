#!/usr/bin/env bash
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive

ADMIN_USER="azureuser"
ADMIN_HOME="/home/$${ADMIN_USER}"

retry() {
  local attempts=0
  local max_attempts=5

  until "$@"; do
    attempts=$((attempts + 1))
    if [[ "$${attempts}" -ge "$${max_attempts}" ]]; then
      return 1
    fi
    sleep $((attempts * 10))
  done
}

retry apt-get update
retry apt-get install -y \
  apt-transport-https \
  ca-certificates \
  curl \
  dbus-x11 \
  gpg \
  git \
  software-properties-common \
  wget \
  xfce4 \
  xfce4-goodies \
  xorg \
  xorgxrdp \
  xrdp

install -d -m 0755 /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --batch --yes --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo \"$VERSION_CODENAME\") stable" \
  > /etc/apt/sources.list.d/docker.list

curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --batch --yes --dearmor -o /etc/apt/keyrings/packages.microsoft.gpg
chmod a+r /etc/apt/keyrings/packages.microsoft.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
  > /etc/apt/sources.list.d/vscode.list

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/edge stable main" \
  > /etc/apt/sources.list.d/edge.list

retry apt-get update
retry apt-get install -y \
  code \
  containerd.io \
  docker-buildx-plugin \
  docker-ce \
  docker-ce-cli \
  docker-compose-plugin \
  microsoft-edge-stable

usermod -aG docker "$${ADMIN_USER}"

printf 'startxfce4\n' > /etc/skel/.xsession
printf 'startxfce4\n' > "$${ADMIN_HOME}/.xsession"
chown "$${ADMIN_USER}:$${ADMIN_USER}" "$${ADMIN_HOME}/.xsession"

adduser xrdp ssl-cert
systemctl enable --now docker
systemctl enable --now xrdp

runuser -l "$${ADMIN_USER}" -c "code --install-extension ms-vscode-remote.remote-containers --force"

# =============================================================================
# Python environment + sample code setup
# =============================================================================

retry apt-get install -y python3 python3-pip python3-venv

# Clone the repository
runuser -l "$${ADMIN_USER}" -c "git clone https://github.com/Ch0wseth/blue-octopus.git $${ADMIN_HOME}/blue-octopus"

# Setup Python virtual environment
WORK_DIR="$${ADMIN_HOME}/blue-octopus/catalog/ai-scenarios/ms-foundry/ms-foundry-model-gateway/src"
runuser -l "$${ADMIN_USER}" -c "python3 -m venv $${WORK_DIR}/venv"
runuser -l "$${ADMIN_USER}" -c "$${WORK_DIR}/venv/bin/pip install -r $${WORK_DIR}/requirements.txt"

# Create .env file with pre-filled values from Terraform
cat > "$${WORK_DIR}/.env" <<EOF
APIM_RESOURCE_GATEWAY_URL="${apim_gateway_url}"
APIM_APIS_SUBSCRIPTION_KEY="${apim_subscription_key}"
FOUNDRY_API_VERSION="2024-05-01-preview"
FOUNDRY_MODEL_NAME="gpt-5.4-mini"
FOUNDRY_DEPLOYMENT_NAME="gpt-5.4-mini"
FOUNDRY_PROJECT_ENDPOINT="${foundry_project_endpoint}"
FOUNDRY_MODEL_GATEWAY_CONNECTION_NAME="ai-gateway"
AZURE_CREDENTIAL_SOURCE="current-user"
EOF
chown "$${ADMIN_USER}:$${ADMIN_USER}" "$${WORK_DIR}/.env"

# Create a convenience shortcut on desktop
runuser -l "$${ADMIN_USER}" -c "mkdir -p $${ADMIN_HOME}/Desktop"
cat > "$${ADMIN_HOME}/Desktop/run-tests.sh" <<'SCRIPT'
#!/usr/bin/env bash
cd ~/blue-octopus/catalog/ai-scenarios/ms-foundry/ms-foundry-model-gateway/src
source venv/bin/activate
echo "=== Environment ready ==="
echo "Run: python main.py        (test APIM direct)"
echo "Run: python agent_main.py  (test Foundry Agent)"
exec bash
SCRIPT
chmod +x "$${ADMIN_HOME}/Desktop/run-tests.sh"
chown "$${ADMIN_USER}:$${ADMIN_USER}" "$${ADMIN_HOME}/Desktop/run-tests.sh"