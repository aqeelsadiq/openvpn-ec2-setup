#!/bin/bash
set -euxo pipefail


LOG_FILE="/var/log/user-data.log"
exec > >(tee -a "${LOG_FILE}") 2>&1
echo "==============================================="
echo " Starting EC2 OpenVPN setup via user-data"
echo "==============================================="

apt update -y
apt install -y openvpn easy-rsa ufw curl rsync awscli tar jq

EIP_ALLOCATION_ID=$(aws ec2 describe-addresses \
  --region us-east-1 \
  --query "Addresses[?AssociationId==null].AllocationId | [0]" \
  --output text)

INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region)

aws ec2 associate-address \
  --allocation-id "${EIP_ALLOCATION_ID}" \
  --instance-id "${INSTANCE_ID}" \
  --region "${REGION}" \
  --allow-reassociation

export DEBIAN_FRONTEND=noninteractive
S3_BUCKET="dev-rhizome-openvpn-bucket"  
BACKUP_FILE="users.tar.gz"

PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)


mkdir -p /etc/openvpn /etc/openvpn/clients /etc/openvpn/easy-rsa /etc/openvpn/groups /etc/openvpn/ccd


if aws s3 ls "s3://${S3_BUCKET}/${BACKUP_FILE}" &>/dev/null; then
  echo "Found backup. Restoring PKI, server keys, clients, and groups..."
  aws s3 cp "s3://${S3_BUCKET}/${BACKUP_FILE}" /tmp/${BACKUP_FILE}
  tar -xzf /tmp/${BACKUP_FILE} -C /
  chown -R root:root /etc/openvpn
  echo "Restore complete."
else
  echo "No backup found. Fresh PKI will be generated."
fi


EASYRSA_DIR="/etc/openvpn/easy-rsa"
if [ ! -f "$EASYRSA_DIR/pki/ca.crt" ] || [ ! -f "/etc/openvpn/ta.key" ] || [ ! -f "/etc/openvpn/server.crt" ]; then
  echo "Generating PKI and server certificates..."
  cp -r /usr/share/easy-rsa/* "$EASYRSA_DIR"
  chown -R root:root "$EASYRSA_DIR"
  cd "$EASYRSA_DIR"

  EASYRSA_BATCH=1 ./easyrsa init-pki
  EASYRSA_BATCH=1 ./easyrsa build-ca nopass

  EASYRSA_BATCH=1 ./easyrsa gen-req server nopass
  EASYRSA_BATCH=1 ./easyrsa sign-req server server

  EASYRSA_BATCH=1 ./easyrsa gen-dh
  openvpn --genkey --secret ta.key

  cp pki/ca.crt pki/issued/server.crt pki/private/server.key pki/dh.pem ta.key /etc/openvpn/

  tar -czf /tmp/${BACKUP_FILE} /etc/openvpn/clients /etc/openvpn/easy-rsa /etc/openvpn/ta.key /etc/openvpn/ca.crt /etc/openvpn/server.crt /etc/openvpn/server.key /etc/openvpn/dh.pem /etc/openvpn/groups /etc/openvpn/ccd
  aws s3 cp /tmp/${BACKUP_FILE} s3://$S3_BUCKET/$BACKUP_FILE
  echo "Initial PKI backup uploaded to S3."
fi

cat <<EOF > /etc/openvpn/server.conf
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
client-config-dir /etc/openvpn/ccd
client-to-client
EOF


sed -i 's/^#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
sysctl -p


ufw allow OpenSSH
ufw allow 1194/udp
sed -i '/^*filter/i *nat\n:POSTROUTING ACCEPT [0:0]\n-A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE\nCOMMIT\n' /etc/ufw/before.rules
sed -i 's/^DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
ufw --force enable


chmod 600 /etc/openvpn/*.key
chmod 644 /etc/openvpn/*.crt /etc/openvpn/*.pem /etc/openvpn/ta.key
chown root:root /etc/openvpn/*


cat <<'EOM' > /usr/local/bin/add-vpn-group.sh
#!/bin/bash
set -euxo pipefail

if [[ -z "$1" ]]; then
  echo "Usage: $0 <group_name> [subnet_third_octet]"
  exit 1
fi

group_name="$1"
subnet_octet="${2:-}"

# Create group directory
GROUP_DIR="/etc/openvpn/groups/$group_name"
mkdir -p "$GROUP_DIR"

# Initialize group metadata
GROUP_META="$GROUP_DIR/group.json"
if [ ! -f "$GROUP_META" ]; then
  # Auto-assign subnet if not provided
  if [ -z "$subnet_octet" ]; then
    # Find the next available subnet (starting from 10.8.1.0)
    used_octets=$(find /etc/openvpn/groups -name "group.json" -exec jq -r '.subnet_third_octet' {} \; 2>/dev/null | sort -n)
    subnet_octet=1
    for used in $used_octets; do
      if [ "$used" == "$subnet_octet" ]; then
        subnet_octet=$((subnet_octet + 1))
      fi
    done
  fi
  
  cat <<EOF > "$GROUP_META"
{
  "name": "$group_name",
  "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "subnet": "10.8.$subnet_octet.0/24",
  "subnet_third_octet": $subnet_octet,
  "members": []
}
EOF
fi

echo "Group '$group_name' created successfully with subnet 10.8.$subnet_octet.0/24"
echo "Group info saved to: $GROUP_META"

# Backup to S3
tar -czf /tmp/users.tar.gz /etc/openvpn/clients /etc/openvpn/easy-rsa /etc/openvpn/ta.key /etc/openvpn/ca.crt /etc/openvpn/server.crt /etc/openvpn/server.key /etc/openvpn/dh.pem /etc/openvpn/groups /etc/openvpn/ccd
aws s3 cp /tmp/users.tar.gz s3://dev-rhizome-openvpn-bucket/users.tar.gz
EOM

chmod +x /usr/local/bin/add-vpn-group.sh

cat <<'EOM' > /usr/local/bin/assign-user-to-group.sh
#!/bin/bash
set -euxo pipefail

if [[ -z "$1" ]] || [[ -z "$2" ]]; then
  echo "Usage: $0 <username> <group_name>"
  exit 1
fi

username="$1"
group_name="$2"

GROUP_DIR="/etc/openvpn/groups/$group_name"
GROUP_META="$GROUP_DIR/group.json"
USER_CCD="/etc/openvpn/ccd/$username"
USER_FILE="$GROUP_DIR/$username"

# Check if group exists
if [ ! -f "$GROUP_META" ]; then
  echo "Error: Group '$group_name' does not exist"
  echo "Create it first with: sudo add-vpn-group.sh $group_name"
  exit 1
fi

# Check if user exists
if [ ! -f "/etc/openvpn/clients/$username.ovpn" ]; then
  echo "Error: User '$username' does not exist"
  echo "Create it first with: sudo add-vpn-user.sh $username"
  exit 1
fi

# Get group subnet
subnet_octet=$(jq -r '.subnet_third_octet' "$GROUP_META")

# Create user file in group directory
touch "$USER_FILE"
echo "User: $username" > "$USER_FILE"
echo "Group: $group_name" >> "$USER_FILE"
echo "Assigned: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$USER_FILE"

# Update group metadata JSON
temp_file=$(mktemp)
jq --arg user "$username" '.members += [$user] | .members |= unique' "$GROUP_META" > "$temp_file"
mv "$temp_file" "$GROUP_META"

# Assign static IP from group subnet (starting from .10)
# Get next available IP in this group's subnet
used_ips=$(grep -l "ifconfig-push 10.8.$subnet_octet" /etc/openvpn/ccd/* 2>/dev/null | \
           xargs grep "ifconfig-push" 2>/dev/null | \
           awk '{print $2}' | \
           awk -F. '{print $4}' | \
           sort -n | tail -1)

if [ -z "$used_ips" ]; then
  next_ip=10
else
  next_ip=$((used_ips + 4))  # OpenVPN uses pairs: .10 and .11, .14 and .15, etc.
fi

client_ip="10.8.$subnet_octet.$next_ip"
server_ip="10.8.$subnet_octet.$((next_ip + 1))"

# Create/Update client-specific config
cat <<EOF > "$USER_CCD"
# User: $username
# Group: $group_name
# Assigned IP: $client_ip
ifconfig-push $client_ip $server_ip
push "route 10.8.$subnet_octet.0 255.255.255.0"
EOF

echo "User '$username' assigned to group '$group_name'"
echo "Assigned IP: $client_ip"
echo "Client config: $USER_CCD"
echo "User file: $USER_FILE"

# Backup to S3
tar -czf /tmp/users.tar.gz /etc/openvpn/clients /etc/openvpn/easy-rsa /etc/openvpn/ta.key /etc/openvpn/ca.crt /etc/openvpn/server.crt /etc/openvpn/server.key /etc/openvpn/dh.pem /etc/openvpn/groups /etc/openvpn/ccd
aws s3 cp /tmp/users.tar.gz s3://dev-rhizome-openvpn-bucket/users.tar.gz
EOM

chmod +x /usr/local/bin/assign-user-to-group.sh

cat <<'EOM' > /usr/local/bin/list-vpn-groups.sh
#!/bin/bash

echo "=== OpenVPN Groups ==="
echo ""

if [ ! -d "/etc/openvpn/groups" ] || [ -z "$(ls -A /etc/openvpn/groups 2>/dev/null)" ]; then
  echo "No groups found."
  exit 0
fi

for group_dir in /etc/openvpn/groups/*; do
  if [ -d "$group_dir" ]; then
    group_name=$(basename "$group_dir")
    meta_file="$group_dir/group.json"
    
    if [ -f "$meta_file" ]; then
      echo "Group: $group_name"
      echo "  Subnet: $(jq -r '.subnet' "$meta_file")"
      echo "  Created: $(jq -r '.created' "$meta_file")"
      echo "  Members: $(jq -r '.members | join(", ")' "$meta_file")"
      echo ""
    fi
  fi
done
EOM

chmod +x /usr/local/bin/list-vpn-groups.sh


cat <<'EOM' > /usr/local/bin/add-vpn-user.sh
#!/bin/bash
set -euxo pipefail

if [[ -z "$1" ]]; then
  echo "Usage: $0 <client_name> [group_name]"
  exit 1
fi

client_name="$1"
group_name="${2:-}"

cd /etc/openvpn/easy-rsa
export EASYRSA_BATCH=1

# Generate client key & sign
./easyrsa gen-req "$client_name" nopass
./easyrsa sign-req client "$client_name"

# Copy to clients folder
mkdir -p /etc/openvpn/clients
cp pki/ca.crt pki/issued/"$client_name".crt pki/private/"$client_name".key /etc/openvpn/clients/

# Generate .ovpn file
PUBLIC_IP=${PUBLIC_IP:-$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)}
cat <<EOF > /etc/openvpn/clients/$client_name.ovpn
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
$(cat /etc/openvpn/clients/ca.crt)
</ca>
<cert>
$(cat /etc/openvpn/clients/$client_name.crt)
</cert>
<key>
$(cat /etc/openvpn/clients/$client_name.key)
</key>
<tls-auth>
$(cat /etc/openvpn/ta.key)
</tls-auth>
EOF

echo "Client config created: /etc/openvpn/clients/$client_name.ovpn"

# If group specified, assign user to group
if [ -n "$group_name" ]; then
  /usr/local/bin/assign-user-to-group.sh "$client_name" "$group_name"
fi

# Backup everything to S3
tar -czf /tmp/users.tar.gz /etc/openvpn/clients /etc/openvpn/easy-rsa /etc/openvpn/ta.key /etc/openvpn/ca.crt /etc/openvpn/server.crt /etc/openvpn/server.key /etc/openvpn/dh.pem /etc/openvpn/groups /etc/openvpn/ccd
aws s3 cp /tmp/users.tar.gz s3://dev-rhizome-openvpn-bucket/users.tar.gz
EOM

chmod +x /usr/local/bin/add-vpn-user.sh



systemctl enable openvpn@server
systemctl restart openvpn@server

if [ ! -f /etc/openvpn/clients/alice.ovpn ]; then
  /usr/local/bin/add-vpn-user.sh alice
fi

echo " OpenVPN setup complete with Group Management!"
echo ""
echo "User Management:"
echo "  - Add user: sudo add-vpn-user.sh <username> [group]"
echo "  - Client files: /etc/openvpn/clients/"
echo ""
echo "Group Management:"
echo "  - Create group: sudo add-vpn-group.sh <group_name>"
echo "  - Assign user: sudo assign-user-to-group.sh <user> <group>"
echo "  - List groups: sudo list-vpn-groups.sh"
echo ""
echo "Backups: s3://${S3_BUCKET}/users.tar.gz"
