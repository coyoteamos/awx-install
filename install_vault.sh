#!/bin/bash

set -e

VAULT_USER="vault"
VAULT_PORT="8200"
DOMAIN_NAME="itp.local"
TLS_DIR="/opt/vault/tls"
PASSWORD_FILE="/root/vault_admin_password.txt"

# Generate random admin password
ADMIN_PASS=$(openssl rand -base64 20)
echo "$ADMIN_PASS" > "$PASSWORD_FILE"
chmod 600 "$PASSWORD_FILE"

# Add HashiCorp APT repo
wget -O- https://apt.releases.hashicorp.com/gpg | \
  gpg --dearmor | \
  sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null

echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
sudo tee /etc/apt/sources.list.d/hashicorp.list

sudo apt update
sudo apt install -y vault jq ufw openssl

# Create Vault user and data dir
if ! id "$VAULT_USER" &>/dev/null; then
  sudo useradd --system --home /etc/vault.d --shell /bin/false $VAULT_USER
fi

sudo mkdir -p /opt/vault/data $TLS_DIR
sudo chown -R $VAULT_USER:$VAULT_USER /opt/vault

# Generate self-signed TLS cert
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout $TLS_DIR/tls.key \
  -out $TLS_DIR/tls.crt \
  -subj "/CN=$DOMAIN_NAME" \
  -addext "subjectAltName=DNS:$DOMAIN_NAME"
sudo chown -R $VAULT_USER:$VAULT_USER $TLS_DIR

# Configure Vault with file storage and HTTPS
cat <<EOF | sudo tee /etc/vault.d/vault.hcl
ui = true

storage "file" {
  path = "/opt/vault/data"
}

listener "tcp" {
  address       = "0.0.0.0:$VAULT_PORT"
  tls_cert_file = "$TLS_DIR/tls.crt"
  tls_key_file  = "$TLS_DIR/tls.key"
}
EOF

sudo chown -R $VAULT_USER:$VAULT_USER /etc/vault.d
sudo chmod 640 /etc/vault.d/vault.hcl

# Start Vault
sudo systemctl enable vault
sudo systemctl start vault
sleep 5

# Open firewall port
sudo ufw allow 22
sudo ufw allow 8200
sudo ufw --force enable

# Initialize Vault and create admin user
export VAULT_ADDR=https://127.0.0.1:$VAULT_PORT
export VAULT_SKIP_VERIFY=true

if vault status | grep -q "Initialized.*false"; then
    vault operator init -key-shares=1 -key-threshold=1 -format=json > ~/vault-init.json

    jq -r '.unseal_keys_b64[0]' ~/vault-init.json > ~/vault_unseal_key.txt
    jq -r '.root_token' ~/vault-init.json > ~/vault_root_token.txt

    vault operator unseal $(cat ~/vault_unseal_key.txt)
    vault login $(cat ~/vault_root_token.txt)

    vault auth enable userpass
    vault policy write admin - <<EOF
path "*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
EOF

    vault write auth/userpass/users/admin \
      password="$ADMIN_PASS" \
      policies="admin"

    echo "✅ Created Vault admin user with random password (stored in $PASSWORD_FILE)"
fi

echo "🚀 Vault is ready at: https://$DOMAIN_NAME:$VAULT_PORT"
echo "🗝️  Unseal key: ~/vault_unseal_key.txt"
echo "🔐 Root token: ~/vault_root_token.txt"