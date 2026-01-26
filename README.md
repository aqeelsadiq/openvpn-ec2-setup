# OpenVPN Terraform & GitHub Actions Setup

**Production-ready OpenVPN on AWS using Terraform, Auto Scaling, and GitHub Actions**

---

## Prerequisites

Before using this project, ensure the following requirements are met:

- AWS account
- Terraform **>= 1.x** installed locally
- AWS CLI configured locally
- An existing EC2 key pair
- A GitHub repository with Actions enabled
- SSH access to the OpenVPN EC2 instances

### AWS Requirements

- IAM user or role with permissions for **EC2, Auto Scaling, and S3**
- An S3 bucket for OpenVPN backups
- An available Elastic IP in the target region

---

## What This Project Does

- Deploys an OpenVPN server on AWS EC2 using Terraform
- Runs OpenVPN inside EC2 instances created via a **Launch Template and Auto Scaling Group**
- Restores VPN state from S3 if an EC2 instance is terminated and a new instance is created
- Manages VPN users and groups via GitHub Actions
- Requires zero manual recovery

---

## Terraform Responsibilities

- Create VPC, subnets, and routing
- Configure security groups
- Create an S3 bucket for backups
- Create an Auto Scaling Group
- Launch EC2 instances with user-data

**User-data script used:**

```text
modules/autoscaling/script.sh

---

### What EC2 User-Data Does (script.sh)

- Install OpenVPN + Easy-RSA
- Auto-attach Elastic IP
- Restore PKI/users from S3 if exists
- Generate PKI on first boot
- Enable CCD + group subnets
- Upload backup after every change

Backup file:

```text
s3://<bucket-name>/users.tar.gz
```
You can Download the File from S3 and Extract it to get the users .ovpn file and groups.

---

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

###  OpenVPN Management Scripts Run Manually on EC2 Instance

```text
/usr/local/bin/add-vpn-user.sh
/usr/local/bin/add-vpn-group.sh
/usr/local/bin/assign-user-to-group.sh
/usr/local/bin/list-vpn-groups.sh
```

Examples: 
**How to Run script manually?**

```bash
sudo add-vpn-group.sh <group-name>
sudo add-vpn-user.sh <usernme> <group-name>
sudo list-vpn-groups.sh
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
.github/workflows/manage-users-groups.yaml
```

Supported actions:

create-users

create-groups

create-users-and-groups

assign-users-to-groups

list-groups

---

### Workflow Inputs

```text
users: alice
groups: engineering
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

1. ASG launches instance
2. user-data runs
3. Restore VPN state from S3
4. Start OpenVPN
5. GitHub Actions connects to all instances

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

### How to Run Code from Start?

1- Clone the repo
2- Navigate to the dev environment:
```text
cd repo-name/envs/dev
```
3- Run the following terraform commands:
Terraform init
Terraform plan
Terraform apply --auto-approve

4- After the infrastructure is created, SSH into the EC2 instance and create users and groups using the commands described above.

5- Download the backup file from S3 and extract it.
6- Navigate to the extracted location and connect to the VPN:
```text
sudo openvpn --config alice.ovpn
```


###  Notes

If you make changes, ensure you also update the following:

S3 bucket name in script.sh

Auto Scaling Group name in the GitHub Actions workflow file
