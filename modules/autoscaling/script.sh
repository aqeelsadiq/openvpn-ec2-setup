#!/bin/bash
set -euxo pipefail

# --- Log all output ---
LOG_FILE="/var/log/user-data.log"
exec > >(tee -a "${LOG_FILE}") 2>&1

echo "==============================================="
echo "✅ Starting EC2 user-data script"
echo "==============================================="

# --- Wait for networking ---
until ping -c1 8.8.8.8 &>/dev/null; do
  echo "Waiting for network..."
  sleep 5
done
echo "Network ready."

# -------------------------------
# Environment setup
# -------------------------------
export DEBIAN_FRONTEND=noninteractive
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
S3_BUCKET="my-openvpn-backups"  # <-- change this to your bucket
BACKUP_FILE="users.tar.gz"

# -------------------------------
# Update & install packages
# -------------------------------
sudo apt update -y
sudo apt install -y openvpn easy-rsa ufw curl rsync awscli
sudo apt install awscli -y
# -------------------------------
# Restore previous users & PKI from S3 if exists
# -------------------------------
sudo mkdir -p /etc/openvpn
sudo mkdir -p /etc/openvpn/clients
sudo mkdir -p /etc/openvpn/easy-rsa

if aws s3 ls "s3://${S3_BUCKET}/${BACKUP_FILE}" &>/dev/null; then
  echo "Found previous backup in S3. Restoring..."
  aws s3 cp "s3://${S3_BUCKET}/${BACKUP_FILE}" /tmp/${BACKUP_FILE}
  sudo tar -xzf /tmp/${BACKUP_FILE} -C /
  sudo chown -R root:root /etc/openvpn
  echo "Restore complete."
else
  echo "No previous backup found. Fresh setup."
fi

# -------------------------------
# Easy-RSA setup (if not already)
# -------------------------------
EASYRSA_DIR="/etc/openvpn/easy-rsa"
if [ ! -f "$EASYRSA_DIR/pki/ca.crt" ]; then
  sudo cp -r /usr/share/easy-rsa/* "$EASYRSA_DIR"
  sudo chown -R root:root "$EASYRSA_DIR"
  cd "$EASYRSA_DIR"

  # Initialize PKI and build CA (non-interactive)
  sudo EASYRSA_BATCH=1 ./easyrsa init-pki
  sudo EASYRSA_BATCH=1 ./easyrsa build-ca nopass

  # Generate server certificates (non-interactive)
  sudo EASYRSA_BATCH=1 ./easyrsa gen-req server nopass
  sudo EASYRSA_BATCH=1 ./easyrsa sign-req server server

  # Diffie-Hellman params and TLS key
  sudo EASYRSA_BATCH=1 ./easyrsa gen-dh
  sudo openvpn --genkey --secret ta.key

  # Admin/client certificate
  sudo EASYRSA_BATCH=1 ./easyrsa gen-req admin nopass
  sudo EASYRSA_BATCH=1 ./easyrsa sign-req client admin

  # Copy to OpenVPN folder
  sudo cp pki/ca.crt pki/issued/server.crt pki/private/server.key pki/dh.pem ta.key /etc/openvpn/
fi

# -------------------------------
# OpenVPN server configuration
# -------------------------------
sudo bash -c 'cat <<EOF > /etc/openvpn/server.conf
port 1194
proto udp
dev tun
ca ca.crt
cert server.crt
key server.key
dh dh.pem
auth SHA256
tls-auth ta.key 0
topology subnet
server 10.8.0.0 255.255.255.0
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 1.1.1.1"
push "dhcp-option DNS 8.8.8.8"
keepalive 10 120
cipher AES-256-CBC
user nobody
group nogroup
persist-key
persist-tun
status openvpn-status.log
verb 3
explicit-exit-notify 1
EOF'

# -------------------------------
# Enable IP forwarding
# -------------------------------
sudo sed -i 's/^#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
sudo sysctl -p

# -------------------------------
# Configure firewall
# -------------------------------
sudo ufw allow OpenSSH
sudo ufw allow 1194/udp
sudo sed -i '/^*filter/i *nat\n:POSTROUTING ACCEPT [0:0]\n-A POSTROUTING -s 10.8.0.0/8 -o eth0 -j MASQUERADE\nCOMMIT\n' /etc/ufw/before.rules
sudo sed -i 's/^DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
sudo ufw --force enable

# -------------------------------
# Start OpenVPN service
# -------------------------------
sudo systemctl enable openvpn@server
sudo systemctl start openvpn@server

# -------------------------------
# Create reusable VPN user script with S3 backup
# -------------------------------
sudo bash -c 'cat <<'"'"'EOM'"'"' > /usr/local/bin/add-vpn-user.sh
#!/bin/bash
set -euxo pipefail

if [[ -z "$1" ]]; then
  echo "Usage: $0 <client_name>"
  exit 1
fi

client_name="$1"
cd /etc/openvpn/easy-rsa
export EASYRSA_BATCH=1

# Generate client key (non-interactive)
sudo EASYRSA_BATCH=1 ./easyrsa gen-req "$client_name" nopass
sudo EASYRSA_BATCH=1 ./easyrsa sign-req client "$client_name"

# Copy client certs to clients folder
sudo mkdir -p /etc/openvpn/clients
sudo cp pki/ca.crt pki/issued/"$client_name".crt pki/private/"$client_name".key /etc/openvpn/clients/

# Generate .ovpn file
PUBLIC_IP=${PUBLIC_IP:-$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)}
sudo bash -c "cat <<EOF > /etc/openvpn/clients/$client_name.ovpn
client
dev tun
proto udp
remote $PUBLIC_IP 1194
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
auth SHA256
cipher AES-256-CBC
key-direction 1
verb 3

<ca>
\$(cat /etc/openvpn/clients/ca.crt)
</ca>
<cert>
\$(cat /etc/openvpn/clients/$client_name.crt)
</cert>
<key>
\$(cat /etc/openvpn/clients/$client_name.key)
</key>
<tls-auth>
\$(cat /etc/openvpn/ta.key)
</tls-auth>
EOF"

# Backup users to S3
sudo tar -czf /tmp/users.tar.gz /etc/openvpn/clients /etc/openvpn/easy-rsa
aws s3 cp /tmp/users.tar.gz s3://'"${S3_BUCKET}"'/users.tar.gz

echo "Client config created: /etc/openvpn/clients/$client_name.ovpn"
EOM'

sudo chmod +x /usr/local/bin/add-vpn-user.sh

# -------------------------------
# Create first VPN user automatically (if not exists)
# -------------------------------
if [ ! -f /etc/openvpn/clients/alice.ovpn ]; then
  sudo add-vpn-user.sh alice
fi

echo "==============================================="
echo "✅ VPN setup complete."
echo "➕ To add a new VPN user, run:"
echo "   sudo add-vpn-user.sh <username>"
echo "Client .ovpn files will be saved in: /etc/openvpn/clients/"
echo "Backups are stored in S3: s3://${S3_BUCKET}/users.tar.gz"
echo "==============================================="












# #!/bin/bash
# set -euxo pipefail
# # --- Log all output ---
# LOG_FILE="/var/log/user-data.log"
# exec > >(tee -a "${LOG_FILE}") 2>&1

# echo "==============================================="
# echo "✅ Starting EC2 user-data script"
# echo "==============================================="

# # --- Wait for networking ---
# until ping -c1 8.8.8.8 &>/dev/null; do
#   echo "Waiting for network..."
#   sleep 5
# done
# echo "Network ready."
# # -------------------------------
# # Environment setup
# # -------------------------------
# export DEBIAN_FRONTEND=noninteractive
# PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

# # -------------------------------
# # Update & install packages
# # -------------------------------
# sudo apt update -y
# sudo apt install -y openvpn easy-rsa ufw curl rsync

# # -------------------------------
# # Easy-RSA setup
# # -------------------------------
# EASYRSA_DIR="/etc/openvpn/easy-rsa"
# sudo mkdir -p "$EASYRSA_DIR"
# sudo cp -r /usr/share/easy-rsa/* "$EASYRSA_DIR"
# sudo chown -R root:root "$EASYRSA_DIR"
# cd "$EASYRSA_DIR"

# # -------------------------------
# # Initialize PKI and build CA (non-interactive)
# # -------------------------------
# sudo EASYRSA_BATCH=1 ./easyrsa init-pki
# sudo EASYRSA_BATCH=1 ./easyrsa build-ca nopass

# # -------------------------------
# # Generate server certificates (non-interactive)
# # -------------------------------
# sudo EASYRSA_BATCH=1 ./easyrsa gen-req server nopass
# sudo EASYRSA_BATCH=1 ./easyrsa sign-req server server

# # Generate Diffie-Hellman parameters and TLS key
# sudo EASYRSA_BATCH=1 ./easyrsa gen-dh
# sudo openvpn --genkey --secret ta.key

# # Generate admin/client certificate
# sudo EASYRSA_BATCH=1 ./easyrsa gen-req admin nopass
# sudo EASYRSA_BATCH=1 ./easyrsa sign-req client admin

# # -------------------------------
# # Copy server files to OpenVPN folder
# # -------------------------------
# sudo mkdir -p /etc/openvpn
# sudo cp pki/ca.crt pki/issued/server.crt pki/private/server.key pki/dh.pem ta.key /etc/openvpn/

# # -------------------------------
# # Create OpenVPN server configuration
# # -------------------------------
# sudo bash -c 'cat <<EOF > /etc/openvpn/server.conf
# port 1194
# proto udp
# dev tun
# ca ca.crt
# cert server.crt
# key server.key
# dh dh.pem
# auth SHA256
# tls-auth ta.key 0
# topology subnet
# server 10.8.0.0 255.255.255.0
# push "redirect-gateway def1 bypass-dhcp"
# push "dhcp-option DNS 1.1.1.1"
# push "dhcp-option DNS 8.8.8.8"
# keepalive 10 120
# cipher AES-256-CBC
# user nobody
# group nogroup
# persist-key
# persist-tun
# status openvpn-status.log
# verb 3
# explicit-exit-notify 1
# EOF'

# # -------------------------------
# # Enable IP forwarding
# # -------------------------------
# sudo sed -i 's/^#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
# sudo sysctl -p

# # -------------------------------
# # Configure firewall
# # -------------------------------
# sudo ufw allow OpenSSH
# sudo ufw allow 1194/udp
# sudo sed -i '/^*filter/i *nat\n:POSTROUTING ACCEPT [0:0]\n-A POSTROUTING -s 10.8.0.0/8 -o eth0 -j MASQUERADE\nCOMMIT\n' /etc/ufw/before.rules
# sudo sed -i 's/^DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
# sudo ufw --force enable

# # -------------------------------
# # Start OpenVPN service
# # -------------------------------
# sudo systemctl enable openvpn@server
# sudo systemctl start openvpn@server

# # -------------------------------
# # Copy Easy-RSA to OpenVPN folder (for client creation)
# # -------------------------------
# sudo cp -r /usr/share/easy-rsa "$EASYRSA_DIR"
# sudo chown -R root:root "$EASYRSA_DIR"

# # -------------------------------
# # Create reusable VPN user script (non-interactive)
# # -------------------------------
# sudo bash -c 'cat <<'"'"'EOM'"'"' > /usr/local/bin/add-vpn-user.sh
# #!/bin/bash
# set -euxo pipefail

# if [[ -z "$1" ]]; then
#   echo "Usage: $0 <client_name>"
#   exit 1
# fi

# client_name="$1"
# cd /etc/openvpn/easy-rsa
# export EASYRSA_BATCH=1

# # Generate client key (non-interactive)
# sudo EASYRSA_BATCH=1 ./easyrsa gen-req "$client_name" nopass
# sudo EASYRSA_BATCH=1 ./easyrsa sign-req client "$client_name"

# # Copy client certs to clients folder
# sudo mkdir -p /etc/openvpn/clients
# sudo cp pki/ca.crt pki/issued/"$client_name".crt pki/private/"$client_name".key /etc/openvpn/clients/

# # Generate .ovpn file
# PUBLIC_IP=${PUBLIC_IP:-$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)}
# sudo bash -c "cat <<EOF > /etc/openvpn/clients/$client_name.ovpn
# client
# dev tun
# proto udp
# remote $PUBLIC_IP 1194
# resolv-retry infinite
# nobind
# persist-key
# persist-tun
# remote-cert-tls server
# auth SHA256
# cipher AES-256-CBC
# key-direction 1
# verb 3

# <ca>
# \$(cat /etc/openvpn/clients/ca.crt)
# </ca>
# <cert>
# \$(cat /etc/openvpn/clients/$client_name.crt)
# </cert>
# <key>
# \$(cat /etc/openvpn/clients/$client_name.key)
# </key>
# <tls-auth>
# \$(cat /etc/openvpn/ta.key)
# </tls-auth>
# EOF"

# echo "Client config created: /etc/openvpn/clients/$client_name.ovpn"
# EOM'

# sudo chmod +x /usr/local/bin/add-vpn-user.sh

# # -------------------------------
# # Create first VPN user automatically
# # -------------------------------
# sudo add-vpn-user.sh alice

# echo "==============================================="
# echo "✅ VPN setup complete."
# echo "➕ To add a new VPN user, run:"
# echo "   sudo add-vpn-user.sh <username>"
# echo "Client .ovpn files will be saved in: /etc/openvpn/clients/"
# echo "==============================================="

