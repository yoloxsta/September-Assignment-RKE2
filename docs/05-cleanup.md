# Cleanup and Teardown Guide

**IMPORTANT**: This guide helps you properly clean up AWS resources to avoid unexpected charges. Always verify all resources are deleted after completing the lab.

## Table of Contents
- [Why Cleanup Matters](#why-cleanup-matters)
- [Cleanup Checklist](#cleanup-checklist)
- [Cleanup via AWS Console](#cleanup-via-aws-console)
- [Cleanup via AWS CLI](#cleanup-via-aws-cli)
- [Cost Estimation](#cost-estimation)
- [Partial Cleanup Options](#partial-cleanup-options)
- [Troubleshooting Cleanup Issues](#troubleshooting-cleanup-issues)

---

## Why Cleanup Matters

### AWS Charges Can Accumulate Quickly

| Resource | Cost per Hour | Cost per Day | Cost per Month |
|----------|--------------|--------------|----------------|
| t3.medium instance | $0.04 | $0.96 | $28.80 |
| m5.large instance | $0.10 | $2.40 | $72.00 |
| 30GB gp3 volume | $0.008 | $0.19 | $5.76 |
| Elastic IP (attached) | Free | Free | Free |
| Elastic IP (unattached) | $0.005 | $0.12 | $3.60 |
| Load Balancer | $0.0225 | $0.54 | $16.20 |
| **Total (lab)** | ~$0.05 | ~$1.15 | ~$34.56 |

**Recommendation**: Always terminate instances when not actively using them!

---

## Cleanup Checklist

Before starting cleanup, note the following from your deployment:

```bash
# Run these commands to gather information
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
SECURITY_GROUP=$(curl -s http://169.254.169.254/latest/meta-data/security-groups)
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)

echo "Instance ID: $INSTANCE_ID"
echo "Security Group: $SECURITY_GROUP"
echo "Region: $REGION"
```

### Items to Clean Up

- [ ] EC2 instances
- [ ] EBS volumes (may be deleted with instance)
- [ ] Security groups (must delete after instances)
- [ ] Key pairs (optional, can keep for future labs)
- [ ] Elastic IPs (if allocated)
- [ ] Load Balancers (if created)
- [ ] VPC resources (if created custom VPC)
- [ ] IAM roles (if created)

---

## Cleanup via AWS Console

### Step 1: Terminate EC2 Instances

1. Navigate to [EC2 Console](https://console.aws.amazon.com/ec2/)
2. Click **Instances** in the left sidebar
3. Select the instance(s) created for this lab:
   - `rke2-lab-server`
   - `rke2-lab-worker-*` (if any)
4. Click **Instance state** → **Terminate instance**
5. Confirm by clicking **Terminate**

**Note**: Termination typically takes 1-2 minutes. Status will change to "Terminated".

### Step 2: Verify Volumes Are Deleted

1. Click **Volumes** in the left sidebar
2. Check for any volumes with status "available"
3. If volumes remain:
   - Select the volume
   - Click **Actions** → **Delete volume**
   - Confirm deletion

**Note**: By default, volumes are set to "Delete on termination" when instance is created. This should happen automatically.

### Step 3: Release Elastic IPs (if allocated)

1. Click **Elastic IPs** in the left sidebar
2. If any IPs are allocated:
   - Select the IP
   - Click **Actions** → **Disassociate** (if associated)
   - Click **Actions** → **Release Elastic IP address**
   - Confirm

### Step 4: Delete Load Balancers (if created)

1. Navigate to [EC2 Console](https://console.aws.amazon.com/ec2/)
2. Click **Load Balancers** in the left sidebar (under Load Balancing)
3. Select any Load Balancers created for this lab
4. Click **Actions** → **Delete**
5. Confirm deletion

### Step 5: Delete Security Groups

1. Click **Security Groups** in the left sidebar
2. Find the security group `rke2-lab-sg`
3. If you can't delete it:
   - Check if any instances are still using it
   - Wait for instances to fully terminate (status: "Terminated")
4. Select the security group
5. Click **Actions** → **Delete security group**
6. Confirm deletion

### Step 6: Clean Up Key Pairs (Optional)

1. Click **Key Pairs** in the left sidebar
2. Select `rke2-lab-key`
3. Click **Actions** → **Delete key pair**
4. Confirm deletion

**Note**: Only delete if you won't use this key again. Save the `.pem` file if you might need it.

### Step 7: Verify Cleanup

1. Check **Instances**: Should show no "Running" instances from lab
2. Check **Volumes**: Should show no "available" volumes
3. Check **Elastic IPs**: Should show no allocated IPs (or only those you intentionally keep)
4. Check **Security Groups**: `rke2-lab-sg` should be deleted

---

## Cleanup via AWS CLI

### Quick Cleanup Script

Create a cleanup script:

```bash
#!/bin/bash
# save as: cleanup-aws.sh

# Configuration
REGION="us-east-1"  # Change to your region
INSTANCE_NAMES="rke2-lab-server rke2-lab-worker-1 rke2-lab-worker-2"
SG_NAME="rke2-lab-sg"
KEY_NAME="rke2-lab-key"

echo "=== RKE2 Lab Cleanup Script ==="
echo "Region: $REGION"
echo ""

# Get instance IDs
echo "Finding instances..."
INSTANCE_IDS=""
for NAME in $INSTANCE_NAMES; do
    ID=$(aws ec2 describe-instances \
        --region $REGION \
        --filters "Name=tag:Name,Values=$NAME" "Name=instance-state-name,Values=running,pending,stopping,stopped" \
        --query "Reservations[].Instances[].InstanceId" \
        --output text)
    
    if [[ -n "$ID" ]]; then
        INSTANCE_IDS="$INSTANCE_IDS $ID"
        echo "  Found: $NAME ($ID)"
    fi
done

# Terminate instances
if [[ -n "$INSTANCE_IDS" ]]; then
    echo ""
    echo "Terminating instances..."
    aws ec2 terminate-instances \
        --region $REGION \
        --instance-ids $INSTANCE_IDS
    
    echo "Waiting for instances to terminate..."
    aws ec2 wait instance-terminated \
        --region $REGION \
        --instance-ids $INSTANCE_IDS
    
    echo "Instances terminated."
else
    echo "No instances found."
fi

# Delete security group
echo ""
echo "Checking security group..."
SG_ID=$(aws ec2 describe-security-groups \
    --region $REGION \
    --group-names $SG_NAME \
    --query "SecurityGroups[0].GroupId" \
    --output text 2>/dev/null)

if [[ -n "$SG_ID" && "$SG_ID" != "None" ]]; then
    echo "Deleting security group: $SG_NAME ($SG_ID)"
    aws ec2 delete-security-group \
        --region $REGION \
        --group-id $SG_ID
    echo "Security group deleted."
else
    echo "Security group not found or already deleted."
fi

# Release Elastic IPs
echo ""
echo "Checking Elastic IPs..."
EIPS=$(aws ec2 describe-addresses \
    --region $REGION \
    --query "Addresses[].AllocationId" \
    --output text)

if [[ -n "$EIPS" ]]; then
    for EIP in $EIPS; do
        echo "Releasing Elastic IP: $EIP"
        aws ec2 release-address \
            --region $REGION \
            --allocation-id $EIP
    done
    echo "Elastic IPs released."
else
    echo "No Elastic IPs to release."
fi

# Delete key pair (optional)
echo ""
read -p "Delete key pair '$KEY_NAME'? (y/N): " DELETE_KEY
if [[ "$DELETE_KEY" == "y" || "$DELETE_KEY" == "Y" ]]; then
    aws ec2 delete-key-pair \
        --region $REGION \
        --key-name $KEY_NAME
    echo "Key pair deleted."
else
    echo "Keeping key pair."
fi

echo ""
echo "=== Cleanup Complete ==="
echo ""
echo "Remaining resources (verify manually):"
echo "  - Volumes: aws ec2 describe-volumes --region $REGION --query 'Volumes[].VolumeId'"
echo "  - Load Balancers: aws elbv2 describe-load-balancers --region $REGION"
```

### Manual CLI Commands

#### List All Lab Resources

```bash
# List instances with "rke2" in name
aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=rke2*" \
    --query "Reservations[].Instances[].{ID:InstanceId,Name:Tags[?Key=='Name'].Value|[0],State:State.Name,Type:InstanceType}" \
    --output table

# List security groups
aws ec2 describe-security-groups \
    --group-names rke2-lab-sg \
    --output table

# List Elastic IPs
aws ec2 describe-addresses --output table

# List Load Balancers
aws elbv2 describe-load-balancers --output table

# List volumes
aws ec2 describe-volumes --output table
```

#### Terminate Instances

```bash
# Get instance ID
INSTANCE_ID=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=rke2-lab-server" "Name=instance-state-name,Values=running" \
    --query "Reservations[0].Instances[0].InstanceId" \
    --output text)

# Terminate
aws ec2 terminate-instances --instance-ids $INSTANCE_ID

# Wait for termination
aws ec2 wait instance-terminated --instance-ids $INSTANCE_ID
```

#### Delete Security Group

```bash
# Get security group ID
SG_ID=$(aws ec2 describe-security-groups \
    --group-names rke2-lab-sg \
    --query "SecurityGroups[0].GroupId" \
    --output text)

# Delete
aws ec2 delete-security-group --group-id $SG_ID
```

#### Release Elastic IP

```bash
# List Elastic IPs
aws ec2 describe-addresses --query "Addresses[].{IP:PublicIp,AllocationId:AllocationId}" --output table

# Release
aws ec2 release-address --allocation-id <ALLOCATION_ID>
```

#### Delete Key Pair

```bash
aws ec2 delete-key-pair --key-name rke2-lab-key
```

---

## Cost Estimation

### Estimate Your Lab Costs

```bash
# Run on the EC2 instance to see uptime
uptime

# Check instance launch time
curl -s http://169.254.169.254/latest/meta-data/launch-time

# Calculate approximate cost
# Hours * $0.04 (t3.medium) = Cost
```

### AWS Cost Explorer

1. Navigate to [AWS Cost Explorer](https://console.aws.amazon.com/cost-management/home)
2. View costs by:
   - Service (EC2, EBS, etc.)
   - Usage type
   - Region

### Set Up Billing Alerts

```bash
# Create budget for $10/month
aws budgets create-budget \
    --account-id <YOUR_ACCOUNT_ID> \
    --budget file://budget.json
```

```json
{
    "BudgetName": "RKE2-Lab-Budget",
    "BudgetLimit": {
        "Amount": "10",
        "Unit": "USD"
    },
    "TimeUnit": "MONTHLY",
    "BudgetType": "COST"
}
```

---

## Partial Cleanup Options

### Option 1: Stop Instead of Terminate

Stop the instance to save money while preserving the RKE2 setup:

```bash
# Stop instance
aws ec2 stop-instances --instance-ids <INSTANCE_ID>

# Start again later
aws ec2 start-instances --instance-ids <INSTANCE_ID>
```

**Pros**:
- Preserves RKE2 installation and configuration
- Quick to restart

**Cons**:
- Still charges for EBS storage (~$0.10/GB/month)
- Elastic IP charges if attached while stopped
- Takes 2-3 minutes to start

### Option 2: Create AMI Before Termination

Create an image to restore later:

```bash
# Create AMI
aws ec2 create-image \
    --instance-id <INSTANCE_ID> \
    --name "rke2-lab-$(date +%Y%m%d)" \
    --description "RKE2 lab server backup"

# List AMIs
aws ec2 describe-images --owners self --query "Images[].{ID:ImageId,Name:Name,Date:CreationDate}" --output table

# Launch from AMI later
aws ec2 run-instances \
    --image-id <AMI_ID> \
    --instance-type t3.medium \
    --key-name rke2-lab-key
```

**Note**: AMIs incur storage charges (~$0.05/GB/month).

### Option 3: Delete Application Only

Keep the cluster, delete the demo app:

```bash
# Delete demo application
kubectl delete namespace demo-app

# Delete any LoadBalancer services
kubectl delete svc traefik-lb -n kube-system 2>/dev/null || true

# Cluster remains running
```

---

## Troubleshooting Cleanup Issues

### Issue: Cannot Delete Security Group

**Error**: "resource has a dependent object"

**Solution**:
1. Check for remaining instances:
   ```bash
   aws ec2 describe-instances \
       --filters "Name=instance.group-name,Values=rke2-lab-sg" \
       --query "Reservations[].Instances[].InstanceId" \
       --output text
   ```

2. Ensure instances are fully terminated (not just "shutting-down")

3. Check for network interfaces:
   ```bash
   aws ec2 describe-network-interfaces \
       --filters "Name=group-name,Values=rke2-lab-sg"
   ```

### Issue: Cannot Terminate Instance

**Error**: "Instance may not be terminated"

**Solution**:
1. Check if termination protection is enabled:
   ```bash
   aws ec2 describe-instance-attribute \
       --instance-id <INSTANCE_ID> \
       --attribute disableApiTermination
   ```

2. Disable termination protection:
   ```bash
   aws ec2 modify-instance-attribute \
       --instance-id <INSTANCE_ID> \
       --no-disable-api-termination
   ```

3. Try termination again

### Issue: Elastic IP Cannot Be Released

**Error**: "address is in use"

**Solution**:
1. Disassociate first:
   ```bash
   aws ec2 disassociate-address \
       --association-id <ASSOCIATION_ID>
   ```

2. Then release:
   ```bash
   aws ec2 release-address \
       --allocation-id <ALLOCATION_ID>
   ```

### Issue: Volume Cannot Be Deleted

**Error**: "volume is in use"

**Solution**:
1. Check attached instances:
   ```bash
   aws ec2 describe-volumes --volume-ids <VOLUME_ID>
   ```

2. Detach if necessary:
   ```bash
   aws ec2 detach-volume --volume-id <VOLUME_ID>
   ```

3. Wait for state "available"

4. Delete:
   ```bash
   aws ec2 delete-volume --volume-id <VOLUME_ID>
   ```

---

## Final Verification

### Checklist

After cleanup, verify:

- [ ] No running instances with "rke2" in name
- [ ] No volumes in "available" state from lab
- [ ] No unattached Elastic IPs
- [ ] Security group "rke2-lab-sg" is deleted
- [ ] No unexpected charges in Cost Explorer

### Verification Commands

```bash
# Check for any remaining EC2 resources
echo "=== Instances ==="
aws ec2 describe-instances \
    --query "Reservations[].Instances[].{ID:InstanceId,Name:Tags[?Key=='Name'].Value|[0],State:State.Name}" \
    --output table

echo ""
echo "=== Volumes ==="
aws ec2 describe-volumes \
    --query "Volumes[].{ID:VolumeId,State:State,Size:Size}" \
    --output table

echo ""
echo "=== Elastic IPs ==="
aws ec2 describe-addresses \
    --query "Addresses[].{IP:PublicIp,Assoc:AssociationId}" \
    --output table

echo ""
echo "=== Security Groups ==="
aws ec2 describe-security-groups \
    --query "SecurityGroups[].{ID:GroupId,Name:GroupName}" \
    --output table
```

---

## Summary

**Key Points**:
1. Always terminate instances when done
2. Verify all resources are deleted
3. Check AWS Cost Explorer regularly
4. Set up billing alerts to catch unexpected charges

**Cost-Saving Tips**:
- Use t3.medium or smaller for labs
- Terminate instances immediately after finishing
- Create AMIs only if needed (they cost money too)
- Use spot instances for short labs (up to 90% discount)

---

## Additional Resources

- [AWS Billing Documentation](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/)
- [AWS Cost Management](https://aws.amazon.com/aws-cost-management/)
- [EC2 Pricing](https://aws.amazon.com/ec2/pricing/)
