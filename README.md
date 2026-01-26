### OpenVPN Terraform & GitHub Actions Setup

```text
Production-ready OpenVPN on AWS using Terraform + Auto Scaling + GitHub Actions
```

---

---

### What This Project Does

```text
✔ Deploys OpenVPN using Terraform
✔ Runs OpenVPN inside an Auto Scaling Group
✔ Restores VPN state from S3 on every boot
✔ Manages users & groups via GitHub Actions
✔ Zero manual recovery required
```

---

###  Terraform Responsibilities

```text
- VPC, subnets, routing
- Security groups
- S3 bucket for backups
- Auto Scaling Group
- EC2 instances with user-data
```

User-data script used:

```text
modules/autoscaling/script.sh
```

---

### EC2 User-Data (script.sh)

```text
- Install OpenVPN + Easy-RSA
- Auto-attach Elastic IP
- Restore PKI/users from S3 if exists
- Generate PKI on first boot
- Enable CCD + group subnets
- Upload backup after every change
```

Backup file:

```text
s3://<bucket-name>/users.tar.gz
```

---

### OpenVPN Configuration

```text
Protocol: UDP
Port: 1194
Cipher: AES-256-CBC
Auth: SHA256
TLS Auth: enabled
Client-to-client: enabled
Group-based subnets: enabled
```

---

### S3 Backup Contents

```text
/etc/openvpn/clients
/etc/openvpn/easy-rsa
/etc/openvpn/groups
/etc/openvpn/ccd
/etc/openvpn/*.crt
/etc/openvpn/*.key
```

---

###  OpenVPN Management Scripts

```text
/usr/local/bin/add-vpn-user.sh
/usr/local/bin/add-vpn-group.sh
/usr/local/bin/assign-user-to-group.sh
/usr/local/bin/list-vpn-groups.sh
```

Examples:

```bash
sudo add-vpn-group.sh engineering
sudo add-vpn-user.sh alice engineering
sudo list-vpn-groups.sh
```

---

### Prerequisites

```text
Before using this project, ensure the following are in place:
```

```text
✔ AWS account
✔ Terraform >= 1.x installed locally
✔ AWS CLI configured locally
✔ An existing EC2 key pair
✔ GitHub repository with Actions enabled
✔ SSH access to OpenVPN EC2 instances
```

AWS requirements:

```text
- IAM user/role with EC2, ASG, S3 permissions
- S3 bucket for OpenVPN backups
- Elastic IP available in target region
```

---

### How to Test (Manual on EC2)

```text
After EC2 is up and OpenVPN is running, SSH into any instance
```

Create a group:

```bash
sudo add-vpn-group.sh engineering
```

Create a user:

```bash
sudo add-vpn-user.sh alice
```

Assign user to group:

```bash
sudo assign-user-to-group.sh alice engineering
```

Verify groups:

```bash
sudo list-vpn-groups.sh
```

Client config location:

```text
/etc/openvpn/clients/alice.ovpn
```

---

### GitHub Actions Workflow

```text
.github/workflows/openvpn.yml
```

Supported actions:

```text
create-users
create-groups
create-users-and-groups
assign-users-to-groups
list-groups
```

---

### Workflow Inputs

```text
users: alice,bob,charlie
groups: engineering,sales,admin
users_with_groups: alice:engineering,bob:sales
user_group_mapping: charlie:admin
```

---

### Required GitHub Secrets

```text
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
AWS_REGION
OPENVPN_SSH_KEY
```

---

###  Auto Scaling Behavior

```text
1. ASG launches instance
2. user-data runs
3. Restore VPN state from S3
4. Start OpenVPN
5. GitHub Actions connects to all instances
```

---

### Default User

```text
alice
```

Client config path:

```text
/etc/openvpn/clients/alice.ovpn
```

---

###  Notes

```text
If the ASG dies, users survive.
This setup is built for real production use.
```
