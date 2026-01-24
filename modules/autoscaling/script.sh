#!/bin/bash
set -euxo pipefail


LOG_FILE="/var/log/user-data.log"
exec > >(tee -a "${LOG_FILE}") 2>&1
echo "Starting EC2 OpenVPN setup via user-data"

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

mkdir -p /etc/openvpn /etc/openvpn/clients /etc/openvpn/easy-rsa


if aws s3 ls "s3://${S3_BUCKET}/${BACKUP_FILE}" &>/dev/null; then
  echo "Found backup. Restoring PKI, server keys, and clients..."
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

  tar -czf /tmp/${BACKUP_FILE} /etc/openvpn/clients /etc/openvpn/easy-rsa /etc/openvpn/ta.key /etc/openvpn/ca.crt /etc/openvpn/server.crt /etc/openvpn/server.key /etc/openvpn/dh.pem
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


cat <<'EOM' > /usr/local/bin/add-vpn-user.sh
#!/bin/bash
set -euxo pipefail

if [[ -z "$1" ]]; then
  echo "Usage: $0 <client_name>"
  exit 1
fi

client_name="$1"
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

# Backup everything to S3
tar -czf /tmp/users.tar.gz /etc/openvpn/clients /etc/openvpn/easy-rsa /etc/openvpn/ta.key /etc/openvpn/ca.crt /etc/openvpn/server.crt /etc/openvpn/server.key /etc/openvpn/dh.pem
aws s3 cp /tmp/users.tar.gz s3://dev-openvpn-bucket-aq/users.tar.gz

echo "Client config created: /etc/openvpn/clients/$client_name.ovpn"
EOM

chmod +x /usr/local/bin/add-vpn-user.sh

systemctl enable openvpn@server
systemctl start openvpn@server

if [ ! -f /etc/openvpn/clients/alice.ovpn ]; then
  add-vpn-user.sh alice
fi

echo " OpenVPN setup complete!"
echo "Add new users with: sudo add-vpn-user.sh <username>"
echo "Client .ovpn files: /etc/openvpn/clients/"
echo "Backups in S3: s3://${S3_BUCKET}/users.tar.gz"