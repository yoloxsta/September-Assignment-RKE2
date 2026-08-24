# AWS EC2 Setup for RKE2

This guide walks you through launching and configuring an EC2 instance for your RKE2 lab.

## Table of Contents
- [Option 1: AWS Console (GUI)](#option-1-aws-console-gui)
- [Option 2: AWS CLI](#option-2-aws-cli)
- [Connect to Your Instance](#connect-to-your-instance)
- [Initial Server Configuration](#initial-server-configuration)
- [Verify Setup](#verify-setup)

---

## Prerequisites Checklist

Before starting, ensure you have:
- [ ] AWS account access
- [ ] AWS Console login OR AWS CLI configured
- [ ] SSH key pair (or create one during launch)
- [ ] Region selected (recommend: us-east-1, us-west-2, or your closest region)

---

## Option 1: AWS Console (GUI)

### Step 1: Navigate to EC2

1. Log into [AWS Console](https://console.aws.amazon.com/)
2. Search for "EC2" in the services search bar
3. Click **EC2** to open the EC2 Dashboard
4. Click **Launch Instance** (orange button)

### Step 2: Configure Instance

#### Name and Tags
```
Name: rke2-lab-server
```

#### Operating System (AMI)
1. Click **Browse more AMIs**
2. Search for: **Amazon Linux 2023**
3. Select: **Amazon Linux 2023 AMI** (free tier eligible)
   - Should show: "Amazon Linux 2023 AMI 2023.x.xxxxxx.x x86_64 (or arm64) HVM kernel-6.1"

#### Instance Type
```
Instance type: t3.medium (2 vCPU, 4 GB RAM)
```
- For better performance: `m5.large` (2 vCPU, 8 GB RAM)
- Budget option: `t3.small` (2 vCPU, 2 GB RAM) - may be tight

#### Key Pair (Login)
1. Click **Create new key pair**
2. Name: `rke2-lab-key`
3. Type: RSA
4. Format: `.pem` (for Mac/Linux/Windows PowerShell) or `.ppk` (for PuTTY)
5. Click **Create key pair**
6. **IMPORTANT**: The file downloads automatically - save it securely!

#### Network Settings

1. Click **Edit** next to Network settings

2. **VPC**: Default (or create a new VPC for lab isolation)

3. **Subnet**: No preference (or select a specific Availability Zone)

4. **Auto-assign public IP**: Enable

5. **Create security group**: Select "Create security group"

6. **Security group name**: `rke2-lab-sg`

7. **Description**: `Security group for RKE2 lab`

8. **Inbound security group rules** - Add the following:

| Type | Protocol | Port Range | Source | Description |
|------|----------|------------|--------|-------------|
| SSH | TCP | 22 | Your IP | SSH access |
| Custom TCP | TCP | 6443 | Anywhere-IPv4 (0.0.0.0/0) | Kubernetes API |
| Custom TCP | TCP | 9345 | Anywhere-IPv4 (0.0.0.0/0) | RKE2 Supervisor |
| Custom TCP | TCP | 80 | Anywhere-IPv4 (0.0.0.0/0) | HTTP Ingress |
| Custom TCP | TCP | 443 | Anywhere-IPv4 (0.0.0.0/0) | HTTPS Ingress |
| Custom UDP | UDP | 8472 | Custom: 10.0.0.0/8 | VXLAN (internal) |
| Custom TCP | TCP | 10250 | Custom: 10.0.0.0/8 | Kubelet |

**Note**: For production, restrict source IPs to known addresses. For this lab, we're using 0.0.0.0/0 for simplicity.

#### Configure Storage

```
Size: 30 GB (minimum 20 GB recommended)
Type: gp3 (General Purpose SSD)
```

#### Advanced Details (Optional)

Expand **Advanced details** and configure:

```
Detailed monitoring: Enable (optional, additional cost)
User data: (leave empty for now, we'll configure RKE2 after launch)
```

### Step 3: Launch Instance

1. Review your configuration in the **Summary** panel
2. Click **Launch Instance**
3. Wait for instance to be in "Running" state (usually 1-2 minutes)

### Step 4: Note Instance Details

After launch, note the following:

```
Instance ID: i-xxxxxxxxxxxxxxxxx
Public IPv4 DNS: ec2-xx-xxx-xxx-xxx.compute-1.amazonaws.com
Public IPv4 address: xx.xxx.xxx.xxx
Private IPv4 address: 10.0.x.x
```

You'll need the **Public IPv4 DNS** or **Public IPv4 address** for SSH access.

---

## Option 2: AWS CLI

If you have AWS CLI installed and configured, you can launch the instance programmatically.

### Step 1: Create Security Group

```bash
# Create security group
aws ec2 create-security-group \
    --group-name rke2-lab-sg \
    --description "Security group for RKE2 lab"

# Note the Group ID returned (sg-xxxxxxxx)

# Add inbound rules
GROUP_ID="sg-xxxxxxxx"  # Replace with your group ID

# SSH access
aws ec2 authorize-security-group-ingress \
    --group-id $GROUP_ID \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0

# Kubernetes API
aws ec2 authorize-security-group-ingress \
    --group-id $GROUP_ID \
    --protocol tcp \
    --port 6443 \
    --cidr 0.0.0.0/0

# RKE2 Supervisor
aws ec2 authorize-security-group-ingress \
    --group-id $GROUP_ID \
    --protocol tcp \
    --port 9345 \
    --cidr 0.0.0.0/0

# HTTP Ingress
aws ec2 authorize-security-group-ingress \
    --group-id $GROUP_ID \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0

# HTTPS Ingress
aws ec2 authorize-security-group-ingress \
    --group-id $GROUP_ID \
    --protocol tcp \
    --port 443 \
    --cidr 0.0.0.0/0

# VXLAN (internal cluster traffic)
aws ec2 authorize-security-group-ingress \
    --group-id $GROUP_ID \
    --protocol udp \
    --port 8472 \
    --cidr 10.0.0.0/8

# Kubelet
aws ec2 authorize-security-group-ingress \
    --group-id $GROUP_ID \
    --protocol tcp \
    --port 10250 \
    --cidr 10.0.0.0/8
```

### Step 2: Create Key Pair

```bash
# Create key pair
aws ec2 create-key-pair \
    --key-name rke2-lab-key \
    --query 'KeyMaterial' \
    --output text > rke2-lab-key.pem

# Set correct permissions (Mac/Linux)
chmod 400 rke2-lab-key.pem

# On Windows PowerShell
# icacls rke2-lab-key.pem /inheritance:r
# icacls rke2-lab-key.pem /grant:r "$env:USERNAME:R"
```

### Step 3: Launch Instance

```bash
# Get the latest Amazon Linux 2023 AMI
AMI_ID=$(aws ec2 describe-images \
    --owners amazon \
    --filters "Name=name,Values=al2023-ami-2023.*-x86_64" \
              "Name=state,Values=available" \
    --query "Images | sort_by(@, &CreationDate) | [-1].ImageId" \
    --output text)

echo "AMI ID: $AMI_ID"

# Launch instance
aws ec2 run-instances \
    --image-id $AMI_ID \
    --count 1 \
    --instance-type t3.medium \
    --key-name rke2-lab-key \
    --security-group-ids $GROUP_ID \
    --block-device-mappings "[{\"DeviceName\":\"/dev/xvda\",\"Ebs\":{\"VolumeSize\":30,\"VolumeType\":\"gp3\"}}]" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=rke2-lab-server}]" \
    --query "Instances[0].InstanceId" \
    --output text
```

### Step 4: Get Instance Details

```bash
# Wait for instance to be running
INSTANCE_ID="i-xxxxxxxxxxxxxxxxx"  # Replace with your instance ID

aws ec2 wait instance-running --instance-ids $INSTANCE_ID

# Get public IP
aws ec2 describe-instances \
    --instance-ids $INSTANCE_ID \
    --query "Reservations[0].Instances[0].PublicIpAddress" \
    --output text

# Get public DNS
aws ec2 describe-instances \
    --instance-ids $INSTANCE_ID \
    --query "Reservations[0].Instances[0].PublicDnsName" \
    --output text
```

---

## Connect to Your Instance

### Step 1: Set Permissions on Key File (Mac/Linux)

```bash
chmod 400 rke2-lab-key.pem
```

### Step 2: Connect via SSH

#### Mac/Linux/Windows PowerShell

```bash
# Replace with your instance's public IP or DNS
ssh -i rke2-lab-key.pem ec2-user@<PUBLIC_IP_OR_DNS>

# Example:
# ssh -i rke2-lab-key.pem ec2-user@ec2-54-123-45-67.compute-1.amazonaws.com
# or
# ssh -i rke2-lab-key.pem ec2-user@54.123.45.67
```

#### Windows Command Prompt

```cmd
ssh -i rke2-lab-key.pem ec2-user@<PUBLIC_IP_OR_DNS>
```

### Step 3: Verify Connection

You should see a welcome message like:

```
   ,     #_
   ~#@  ###
   @#@  ###
   @#@  ###
   @#@  ###
   @#@  ###
   @#@  ###
   @#@  ####
####   ####
   ####   ####
    ####   ####
   ####   ####
      ####   ####
       ####   ####
        ####   ####
         ####   ####
          ####   ####
           ####   ####
            ####   ####
             ####   ####
              ####   ####
               ####   ####
                ####   ####
                 ####   ####
                  ####   ####
                   ####   ####
                    ####   ####
                     ####   ####
                      ####   ####
                       ####   ####
                        ####   ####
                         ####   ####
                          ####   ####
                           ####   ####
                            ####   ####
                             ####   ####
                              ####   ####
                               ####   ####
                                ####   ####
                                 ####   ####
                                  ####   ####
                                   ####   ####
                                    ####   ####
                                     ####   ####
                                      ####   ####
                                       ####   ####
                                        ####   ####
                                         ####   ####
                                          ####   ####
                                           ####   ####
                                            ####   ####
                                             ####   ####
                                              ####   ####
                                               ####   ####
                                                ####   ####
                                                 ####   ####
                                                  ####   ####
                                                   ####   ####
                                                    ####   ####
                                                     ####   ####
                                                      ####   ####
                                                       ####   ####
                                                        ####   ####
                                                         ####   ####
                                                          ####   ####
                                                           ####   ####
                                                            ####   ####
                                                             ####   ####
                                                              ####   ####
                                                               ####   ####
                                                                ####   ####
                                                                 ####   ####
                                                                  ####   ####
                                                                   ####   ####
                                                                    ####   ####
                                                                     ####   ####
                                                                      ####   ####
                                                                       ####   ####
                                                                        ####   ####
                                                                         ####   ####
                                                                          ####   ####
                                                                           ####   ####
                                                                            ####   ####
                                                                             ####   ####
                                                                              ####   ####
                                                                               ####   ####
                                                                                ####   ####
                                                                                 ####   ####
                                                                                  ####   ####
                                                                                   ####   ####
                                                                                    ####   ####
                                                                                     ####   ####
                                                                                      ####   ####
                                                                                       ####   ####
                                                                                        ####   ####
                                                                                         ####   ####
                                                                                          ####   ####
                                                                                           ####   ####
                                                                                            ####   ####
                                                                                             ####   ####
                                                                                              ####   ####
                                                                                               ####   ####
                                                                                                ####   ####
                                                                                                 ####   ####
                                                                                                  ####   ####
                                                                                                   ####   ####
                                                                                                    ####   ####
                                                                                                     ####   ####
                                                                                                      ####   ####
                                                                                                       ####   ####
                                                                                                        ####   ####
                                                                                                         ####   ####
                                                                                                          ####   ####
                                                                                                           ####   ####
                                                                                                            ####   ####
                                                                                                             ####   ####
                                                                                                              ####   ####
                                                                                                               ####   ####
                                                                                                                ####   ####
                                                                                                                 ####   ####
                                                                                                                  ####   ####
                                                                                                                   ####   ####
                                                                                                                    ####   ####
                                                                                                                     ####   ####
                                                                                                                      ####   ####
                                                                                                                       ####   ####
                                                                                                                        ####   ####
                                                                                                                         ####   ####
                                                                                                                          ####   ####
                                                                                                                           ####   ####
                                                                                                                            ####   ####
                                                                                                                             ####   ####
                                                                                                                              ####   ####
                                                                                                                               ####   ####
                                                                                                                                ####   ####
                                                                                                                                 ####   ####
                                                                                                                                  ####   ####
                                                                                                                                   ####   ####
                                                                                                                                    ####   ####
                                                                                                                                     ####   ####
                                                                                                                                      ####   ####
                                                                                                                                       ####   ####
                                                                                                                                        ####   ####
                                                                                                                                         ####   ####
                                                                                                                                          ####   ####
                                                                                                                                           ####   ####
                                                                                                                                            ####   ####
                                                                                                                                             ####   ####
                                                                                                                                              ####   ####
                                                                                                                                               ####   ####
                                                                                                                                                ####   ####
                                                                                                                                                 ####   ####
                                                                                                                                                  ####   ####
                                                                                                                                                   ####   ####
                                                                                                                                                    ####   ####
                                                                                                                                                     ####   ####
                                                                                                                                                      ####   ####
                                                                                                                                                       ####   ####
                                                                                                                                                        ####   ####
                                                                                                                                                         ####   ####
                                                                                                                                                          ####   ####
                                                                                                                                                           ####   ####
                                                                                                                                                            ####   ####
                                                                                                                                                             ####   ####
                                                                                                                                                              ####   ####
                                                                                                                                                               ####   ####
                                                                                                                                                                ####   ####
                                                                                                                                                                 ####   ####
                                                                                                                                                                  ####   ####
                                                                                                                                                                   ####   ####
                                                                                                                                                                    ####   ####
                                                                                                                                                                     ####   ####
                                                                                                                                                                      ####   ####
                                                                                                                                                                       ####   ####
                                                                                                                                                                        ####   ####
                                                                                                                                                                         ####   ####
                                                                                                                                                                          ####   ####
                                                                                                                                                                           ####   ####
                                                                                                                                                                            ####   ####
                                                                                                                                                                             ####   ####
                                                                                                                                                                              ####   ####
                                                                                                                                                                               ####   ####
                                                                                                                                                                                ####   ####
                                                                                                                                                                                 ####   ####
                                                                                                                                                                                  ####   ####
                                                                                                                                                                                   ####   ####
                                                                                                                                                                                    ####   ####
                                                                                                                                                                                     ####   ####
                                                                                                                                                                                      ####   ####
                                                                                                                                                                                       ####   ####
                                                                                                                                                                                        ####   ####
                                                                                                                                                                                         ####   ####
                                                                                                                                                                                          ####   ####
                                                                                                                                                                                           ####   ####
                                                                                                                                                                                            ####   ####
                                                                                                                                                                                             ####   ####
                                                                                                                                                                                              ####   ####
                                                                                                                                                                                               ####   ####
                                                                                                                                                                                                ####   ####
                                                                                                                                                                                                 ####   ####
                                                                                                                                                                                                  ####   ####
                                                                                                                                                                                                   ####   ####
                                                                                                                                                                                                    ####   ####
                                                                                                                                                                                                     ####   ####
                                                                                                                                                                                                      ####   ####
                                                                                                                                                                                                       ####   ####
                                                                                                                                                                                                        ####   ####
                                                                                                                                                                                                         ####   ####
                                                                                                                                                                                                          ####   ####
                                                                                                                                                                                                           ####   ####
                                                                                                                                                                                                            ####   ####
                                                                                                                                                                                                             ####   ####
                                                                                                                                                                                                              ####   ####
                                                                                                                                                                                                               ####   ####
                                                                                                                                                                                                                ####   ####
                                                                                                                                                                                                                 ####   ####
                                                                                                                                                                                                                  ####   ####
                                                                                                                                                                                                                   ####   ####
                                                                                                                                                                                                                    ####   ####
                                                                                                                                                                                                                     ####   ####
                                                                                                                                                                                                                      ####   ####
                                                                                                                                                                                                                       ####   ####
                                                                                                                                                                                                                        ####   ####
                                                                                                                                                                                                                         ####   ####
                                                                                                                                                                                                                          ####   ####
                                                                                                                                                                                                                           ####   ####
                                                                                                                                                                                                                            ####   ####
                                                                                                                                                                                                                             ####   ####
                                                                                                                                                                                                                              ####   ####
                                                                                                                                                                                                                               ####   ####
                                                                                                                                                                                                                                ####   ####
                                                                                                                                                                                                                                 ####   ####
                                                                                                                                                                                                                                  ####   ####
                                                                                                                                                                                                                                   ####   ####
                                                                                                                                                                                                                                    ####   ####
                                                                                                                                                                                                                                     ####   ####
                                                                                                                                                                                                                                      ####   ####
                                                                                                                                                                                                                                       ####   ####
                                                                                                                                                                                                                                        ####   ####
                                                                                                                                                                                                                                         ####   ####
                                                                                                                                                                                                                                          ####   ####
                                                                                                                                                                                                                                           ####   ####
                                                                                                                                                                                                                                            ####   ####
                                                                                                                                                                                                                                             ####   ####
                                                                                                                                                                                                                                              ####   ####
                                                                                                                                                                                                                                               ####   ####
                                                                                                                                                                                                                                                ####   ####
                                                                                                                                                                                                                                                 ####   ####
                                                                                                                                                                                                                                                  ####   ####
                                                                                                                                                                                                                                                   ####   ####
                                                                                                                                                                                                                                                    ####   ####
                                                                                                                                                                                                                                                     ####   ####
                                                                                                                                                                                                                                                      ####   ####
                                                                                                                                                                                                                                                       ####   ####
                                                                                                                                                                                                                                                        ####   ####
                                                                                                                                                                                                                                                         ####   ####
                                                                                                                                                                                                                                                          ####   ####
                                                                                                                                                                                                                                                           ####   ####
                                                                                                                                                                                                                                                            ####   ####
                                                                                                                                                                                                                                                             ####   ####
                                                                                                                                                                                                                                                              ####   ####
                                                                                                                                                                                                                                                               ####   ####
                                                                                                                                                                                                                                                                ####   ####
                                                                                                                                                                                                                                                                 ####   ####
                                                                                                                                                                                                                                                                  ####   ####
                                                                                                                                                                                                                                                                   ####   ####
                                                                                                                                                                                                                                                                    ####   ####
                                                                                                                                                                                                                                                                     ####   ####
                                                                                                                                                                                                                                                                      ####   ####
                                                                                                                                                                                                                                                                       ####   ####
                                                                                                                                                                                                                                                                        ####   ####
                                                                                                                                                                                                                                                                         ####   ####
                                                                                                                                                                                                                                                                          ####   ####
                                                                                                                                                                                                                                                                           ####   ####
                                                                                                                                                                                                                                                                            ####   ####
                                                                                                                                                                                                                                                                             ####   ####
                                                                                                                                                                                                                                                                              ####   ####
                                                                                                                                                                                                                                                                               ####   ####
                                                                                                                                                                                                                                                                                ####   ####
                                                                                                                                                                                                                                                                                 ####   ####
                                                                                                                                                                                                                                                                                  ####   ####
                                                                                                                                                                                                                                                                                   ####   ####
                                                                                                                                                                                                                                                                                    ####   ####
                                                                                                                                                                                                                                                                                     ####   ####
                                                                                                                                                                                                                                                                                      ####   ####
                                                                                                                                                                                                                                                                                       ####   ####
                                                                                                                                                                                                                                                                                        ####   ####
                                                                                                                                                                                                                                                                                         ####   ####
                                                                                                                                                                                                                                                                                          ####   ####
                                                                                                                                                                                                                                                                                           ####   ####
                                                                                                                                                                                                                                                                                            ####   ####
                                                                                                                                                                                                                                                                                             ####   ####
                                                                                                                                                                                                                                                                                              ####   ####
                                                                                                                                                                                                                                                                                               ####   ####
                                                                                                                                                                                                                                                                                                ####   ####
                                                                                                                                                                                                                                                                                                 ####   ####
                                                                                                                                                                                                                                                                                                  ####   ####
                                                                                                                                                                                                                                                                                                   ####   ####
                                                                                                                                                                                                                                                                                                    ####   ####
                                                                                                                                                                                                                                                                                                     ####   ####
                                                                                                                                                                                                                                                                                                      ####   ####
                                                                                                                                                                                                                                                                                                       ####   ####
                                                                                                                                                                                                                                                                                                        ####   ####
                                                                                                                                                                                                                                                                                                         ####   ####
                                                                                                                                                                                                                                                                                                          ####   ####
                                                                                                                                                                                                                                                                                                           ####   ####
                                                                                                                                                                                                                                                                                                            ####   ####
                                                                                                                                                                                                                                                                                                             ####   ####
                                                                                                                                                                                                                                                                                                              ####   ####
                                                                                                                                                                                                                                                                                                               ####   ####
                                                                                                                                                                                                                                                                                                                ####   ####
                                                                                                                                                                                                                                                                                                                 ####   ####
                                                                                                                                                                                                                                                                                                                  ####   ####
                                                                                                                                                                                                                                                                                                                   ####   ####
                                                                                                                                                                                                                                                                                                                    ####   ####
                                                                                                                                                                                                                                                                                                                     ####   ####
                                                                                                                                                                                                                                                                                                                      ####   ####
                                                                                                                                                                                                                                                                                                                       ####   ####
                                                                                                                                                                                                                                                                                                                        ####   ####
                                                                                                                                                                                                                                                                                                                         ####   ####
                                                                                                                                                                                                                                                                                                                          ####   ####
                                                                                                                                                                                                                                                                                                                           ####   ####
                                                                                                                                                                                                                                                                                                                            ####   ####
                                                                                                                                                                                                                                                                                                                             ####   ####
                                                                                                                                                                                                                                                                                                                              ####   ####
                                                                                                                                                                                                                                                                                                                               ####   ####
                                                                                                                                                                                                                                                                                                                                ####   ####
                                                                                                                                                                                                                                                                                                                                 ####   ####
                                                                                                                                                                                                                                                                                                                                  ####   ####
                                                                                                                                                                                                                                                                                                                                   ####   ####
                                                                                                                                                                                                                                                                                                                                    ####   ####
                                                                                                                                                                                                                                                                                                                                     ####   ####
                                                                                                                                                                                                                                                                                                                                      ####   ####
                                                                                                                                                                                                                                                                                                                                       ####   ####
                                                                                                                                                                                                                                                                                                                                        ####   ####
                                                                                                                                                                                                                                                                                                                                         ####   ####
                                                                                                                                                                                                                                                                                                                                          ####   ####
                                                                                                                                                                                                                                                                                                                                           ####   ####
                                                                                                                                                                                                                                                                                                                                            ####   ####
                                                                                                                                                                                                                                                                                                                                             ####   ####
                                                                                                                                                                                                                                                                                                                                              ####   ####
                                                                                                                                                                                                                                                                                                                                               ####   ####
                                                                                                                                                                                                                                                                                                                                                ####   ####
                                                                                                                                                                                                                                                                                                                                                 ####   ####
                                                                                                                                                                                                                                                                                                                                                  ####   ####
                                                                                                                                                                                                                                                                                                                                                   ####   ####
                                                                                                                                                                                                                                                                                                                                                    ####   ####
                                                                                                                                                                                                                                                                                                                                                     ####   ####
                                                                                                                                                                                                                                                                                                                                                      ####   ####
                                                                                                                                                                                                                                                                                                                                                       ####   ####
                                                                                                                                                                                                                                                                                                                                                        ####   ####
                                                                                                                                                                                                                                                                                                                                                         ####   ####
                                                                                                                                                                                                                                                                                                                                                          ####   ####
                                                                                                                                                                                                                                                                                                                                                           ####   ####
                                                                                                                                                                                                                                                                                                                                                            ####   ####
                                                                                                                                                                                                                                                                                                                                                             ####   ####
                                                                                                                                                                                                                                                                                                                                                              ####   ####
                                                                                                                                                                                                                                                                                                                                                               ####   ####
                                                                                                                                                                                                                                                                                                                                                                ####   ####
                                                                                                                                                                                                                                                                                                                                                                 ####   ####
                                                                                                                                                                                                                                                                                                                                                                  ####   ####
                                                                                                                                                                                                                                                                                                                                                                   ####   ####
                                                                                                                                                                                                                                                                                                                                                                    ####   ####
                                                                                                                                                                                                                                                                                                                                                                     ####   ####
                                                                                                                                                                                                                                                                                                                                                                      ####   ####
                                                                                                                                                                                                                                                                                                                                                                       ####   ####
                                                                                                                                                                                                                                                                                                                                                                        ####   ####
                                                                                                                                                                                                                                                                                                                                                                         ####   ####
                                                                                                                                                                                                                                                                                                                                                                          ####   ####
                                                                                                                                                                                                                                                                                                                                                                           ####   ####
                                                                                                                                                                                                                                                                                                                                                                            ####   ####
                                                                                                                                                                                                                                                                                                                                                                             ####   ####
                                                                                                                                                                                                                                                                                                                                                                              ####   ####
                                                                                                                                                                                                                                                                                                                                                                               ####   ####
                                                                                                                                                                                                                                                                                                                                                                                ####   ####
                                                                                                                                                                                                                                                                                                                                                                                 ####   ####
                                                                                                                                                                                                                                                                                                                                                                                  ####   ####
                                                                                                                                                                                                                                                                                                                                                                                   ####   ####
                                                                                                                                                                                                                                                                                                                                                                                    ####   ####
                                                                                                                                                                                                                                                                                                                                                                                     ####   ####
                                                                                                                                                                                                                                                                                                                                                                                      ####   ####
                                                                                                                                                                                                                                                                                                                                                                                       ####   ####
                                                                                                                                                                                                                                                                                                                                                                                        ####   ####
                                                                                                                                                                                                                                                                                                                                                                                         ####   ####
                                                                                                                                                                                                                                                                                                                                                                                          ####   ####
                                                                                                                                                                                                                                                                                                                                                                                           ####   ####
                                                                                                                                                                                                                                                                                                                                                                                            ####   ####
                                                                                                                                                                                                                                                                                                                                                                                             ####   ####
                                                                                                                                                                                                                                                                                                                                                                                              ####   ####
                                                                                                                                                                                                                                                                                                                                                                                               ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                 ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                  ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                   ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                    ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                     ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                      ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                       ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                        ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                         ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                          ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                           ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                            ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                             ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                              ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                               ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                 ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                  ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                   ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                    ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                     ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                      ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                       ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                        ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                         ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                          ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                           ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                            ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                             ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                              ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                               ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                 ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                  ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                   ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                    ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                     ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                      ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                       ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                        ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                         ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                          ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                           ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                            ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                             ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                              ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                               ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                 ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                  ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                   ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                    ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                     ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                      ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                       ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                        ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                         ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                          ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                           ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                            ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                             ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                              ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                               ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                 ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                  ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                   ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                    ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                     ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                      ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                       ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                        ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                         ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                          ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                           ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                            ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                             ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                              ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                               ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             ####   ####
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              ####   ####
                                                                                                                                                                                                                           [ec2-user@ip-10-0-1-123 ~]$
```

---

## Initial Server Configuration

Once connected, run these commands to prepare the system for RKE2.

### Step 1: Update System

```bash
# Update all packages
sudo dnf update -y
```

### Step 2: Install Required Packages

```bash
# Install dependencies
sudo dnf install -y \
  curl \
  wget \
  git \
  conntrack \
  socat \
  nfs-utils \
  iptables \
  iptables-nft
```

### Step 3: Configure Kernel Modules

```bash
# Load required kernel modules
sudo modprobe overlay
sudo modprobe br_netfilter

# Persist modules across reboot
cat <<EOF | sudo tee /etc/modules-load.d/rke2.conf
overlay
br_netfilter
EOF
```

### Step 4: Configure System Settings

```bash
# Configure sysctl for Kubernetes networking
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# Apply settings
sudo sysctl --system
```

### Step 5: Disable Swap

```bash
# Disable swap (Kubernetes requirement)
sudo swapoff -a

# Verify swap is disabled
free -h
# Should show 0 for swap
```

### Step 6: Set Hostname (Optional)

```bash
# Set a meaningful hostname (helps identify the node)
sudo hostnamectl set-hostname rke2-server-1

# Update /etc/hosts
echo "$(hostname -I | awk '{print $1}') $(hostname)" | sudo tee -a /etc/hosts
```

---

## Verify Setup

Run these commands to verify your EC2 instance is ready for RKE2:

```bash
# Check OS version
cat /etc/os-release

# Check kernel version
uname -r

# Verify modules are loaded
lsmod | grep -E "overlay|br_netfilter"

# Verify sysctl settings
sysctl net.bridge.bridge-nf-call-iptables
sysctl net.ipv4.ip_forward

# Check swap is disabled
free -h

# Check available resources
echo "CPU: $(nproc) cores"
echo "RAM: $(free -h | awk '/^Mem:/ {print $2}')"
echo "Disk: $(df -h / | awk 'NR==2 {print $4}') available"
```

### Expected Output

```
[ec2-user@rke2-server-1 ~]$ cat /etc/os-release
NAME="Amazon Linux"
VERSION="2023"
...

[ec2-user@rke2-server-1 ~]$ free -h
               total        used        free      shared  buff/cache   available
Mem:           3.6Gi       200Mi       3.2Gi        10Mi       300Mi       3.2Gi
Swap:             0B          0B          0B

[ec2-user@rke2-server-1 ~]$ echo "CPU: $(nproc) cores"
CPU: 2 cores

[ec2-user@rke2-server-1 ~]$ echo "RAM: $(free -h | awk '/^Mem:/ {print $2}')"
RAM: 3.6Gi

[ec2-user@rke2-server-1 ~]$ echo "Disk: $(df -h / | awk 'NR==2 {print $4}') available"
Disk: 28Gi available
```

---

## Next Steps

Your EC2 instance is now ready! Continue to:
- **[02-rke2-installation.md](02-rke2-installation.md)** - Install and configure RKE2

---

## Troubleshooting

### Cannot Connect via SSH

1. **Check security group**: Ensure port 22 is open
2. **Check key permissions**: `chmod 400 rke2-lab-key.pem`
3. **Use correct user**: Amazon Linux uses `ec2-user`
4. **Check instance state**: Must be "Running"

### Connection Timeout

1. Verify public IP address
2. Check if instance is in a public subnet
3. Verify security group rules

### Permission Denied

1. Ensure you're using the correct key file
2. Check key file permissions (should be 400)
3. Verify key pair matches the instance

---

## Cost Reminder

**Remember to terminate your instance when not in use!**

```bash
# Via AWS CLI
aws ec2 terminate-instances --instance-ids i-xxxxxxxxxxxxxxxxx
```

Or via AWS Console: EC2 → Instances → Select → Instance State → Terminate
