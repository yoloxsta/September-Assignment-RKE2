#!/bin/bash
#
# RKE2 Lab AWS Cleanup Script
# This script cleans up all AWS resources created for the RKE2 lab
#
# Usage:
#   chmod +x cleanup-aws.sh
#   ./cleanup-aws.sh
#
# Prerequisites:
#   - AWS CLI installed and configured
#   - Appropriate IAM permissions
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
REGION=${AWS_REGION:-"us-east-1"}
INSTANCE_NAMES="rke2-lab-server rke2-lab-worker-1 rke2-lab-worker-2"
SG_NAME="rke2-lab-sg"
KEY_NAME="rke2-lab-key"

# Confirm cleanup
echo -e "${RED}======================================"
echo "RKE2 Lab AWS Cleanup Script"
echo "======================================${NC}"
echo ""
echo "This script will DELETE the following resources:"
echo "  - EC2 instances: ${INSTANCE_NAMES}"
echo "  - Security group: ${SG_NAME}"
echo "  - Key pair: ${KEY_NAME} (optional)"
echo "  - Elastic IPs (if any)"
echo "  - Load Balancers (if any)"
echo ""
echo -e "${YELLOW}WARNING: This action cannot be undone!${NC}"
echo ""

read -p "Continue with cleanup? (yes/no): " CONFIRM

if [[ "$CONFIRM" != "yes" ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo ""
echo "Region: $REGION"
echo ""

# ============================================
# 1. Find and Terminate Instances
# ============================================
echo -e "${BLUE}Step 1: Finding and terminating instances...${NC}"

INSTANCE_IDS=""

for NAME in $INSTANCE_NAMES; do
    ID=$(aws ec2 describe-instances \
        --region $REGION \
        --filters "Name=tag:Name,Values=$NAME" "Name=instance-state-name,Values=running,pending,stopping,stopped" \
        --query "Reservations[].Instances[].InstanceId" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$ID" ]]; then
        INSTANCE_IDS="$INSTANCE_IDS $ID"
        echo "  Found: $NAME ($ID)"
    fi
done

if [[ -n "$INSTANCE_IDS" ]]; then
    echo ""
    echo "  Terminating instances..."
    aws ec2 terminate-instances \
        --region $REGION \
        --instance-ids $INSTANCE_IDS \
        --output table
    
    echo ""
    echo "  Waiting for instances to terminate..."
    for ID in $INSTANCE_IDS; do
        aws ec2 wait instance-terminated \
            --region $REGION \
            --instance-ids $ID 2>/dev/null || true
    done
    
    echo -e "  ${GREEN}✓ Instances terminated${NC}"
else
    echo "  No instances found."
fi

echo ""

# ============================================
# 2. Delete Load Balancers
# ============================================
echo -e "${BLUE}Step 2: Checking for Load Balancers...${NC}"

LBS=$(aws elbv2 describe-load-balancers \
    --region $REGION \
    --query "LoadBalancers[].LoadBalancerArn" \
    --output text 2>/dev/null || echo "")

if [[ -n "$LBS" ]]; then
    echo "  Found Load Balancers:"
    for LB_ARN in $LBS; do
        LB_NAME=$(echo $LB_ARN | awk -F'/' '{print $NF}' | awk -F':' '{print $1}')
        echo "    - $LB_NAME"
        
        aws elbv2 delete-load-balancer \
            --region $REGION \
            --load-balancer-arn $LB_ARN
        
        echo "      Deleted"
    done
    
    # Wait for deletion
    echo "  Waiting for Load Balancers to delete..."
    sleep 10
    
    echo -e "  ${GREEN}✓ Load Balancers deleted${NC}"
else
    echo "  No Load Balancers found."
fi

echo ""

# ============================================
# 3. Release Elastic IPs
# ============================================
echo -e "${BLUE}Step 3: Checking Elastic IPs...${NC}"

EIPS=$(aws ec2 describe-addresses \
    --region $REGION \
    --query "Addresses[].AllocationId" \
    --output text 2>/dev/null || echo "")

if [[ -n "$EIPS" ]]; then
    echo "  Found Elastic IPs:"
    for EIP in $EIPS; do
        PUBLIC_IP=$(aws ec2 describe-addresses \
            --region $REGION \
            --allocation-ids $EIP \
            --query "Addresses[0].PublicIp" \
            --output text)
        
        echo "    - $PUBLIC_IP ($EIP)"
        
        # Disassociate if needed
        ASSOC_ID=$(aws ec2 describe-addresses \
            --region $REGION \
            --allocation-ids $EIP \
            --query "Addresses[0].AssociationId" \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$ASSOC_ID" && "$ASSOC_ID" != "None" ]]; then
            aws ec2 disassociate-address \
                --region $REGION \
                --association-id $ASSOC_ID
            echo "      Disassociated"
        fi
        
        # Release
        aws ec2 release-address \
            --region $REGION \
            --allocation-id $EIP
        
        echo "      Released"
    done
    
    echo -e "  ${GREEN}✓ Elastic IPs released${NC}"
else
    echo "  No Elastic IPs found."
fi

echo ""

# ============================================
# 4. Delete Security Group
# ============================================
echo -e "${BLUE}Step 4: Deleting security group...${NC}"

SG_ID=$(aws ec2 describe-security-groups \
    --region $REGION \
    --group-names $SG_NAME \
    --query "SecurityGroups[0].GroupId" \
    --output text 2>/dev/null || echo "")

if [[ -n "$SG_ID" && "$SG_ID" != "None" ]]; then
    echo "  Security group: $SG_NAME ($SG_ID)"
    
    # Retry deletion (instances may still be cleaning up)
    MAX_RETRIES=5
    RETRY=0
    
    while [[ $RETRY -lt $MAX_RETRIES ]]; do
        if aws ec2 delete-security-group \
            --region $REGION \
            --group-id $SG_ID 2>/dev/null; then
            echo -e "  ${GREEN}✓ Security group deleted${NC}"
            break
        else
            RETRY=$((RETRY+1))
            if [[ $RETRY -lt $MAX_RETRIES ]]; then
                echo "  Waiting for dependencies to clear... ($RETRY/$MAX_RETRIES)"
                sleep 10
            fi
        fi
    done
    
    if [[ $RETRY -eq $MAX_RETRIES ]]; then
        echo -e "  ${YELLOW}⚠ Could not delete security group. Please delete manually.${NC}"
    fi
else
    echo "  Security group not found or already deleted."
fi

echo ""

# ============================================
# 5. Delete Key Pair (Optional)
# ============================================
echo -e "${BLUE}Step 5: Key pair cleanup...${NC}"

KEY_EXISTS=$(aws ec2 describe-key-pairs \
    --region $REGION \
    --key-names $KEY_NAME \
    --query "KeyPairs[0].KeyName" \
    --output text 2>/dev/null || echo "")

if [[ -n "$KEY_EXISTS" && "$KEY_EXISTS" != "None" ]]; then
    read -p "Delete key pair '$KEY_NAME'? (y/N): " DELETE_KEY
    
    if [[ "$DELETE_KEY" == "y" || "$DELETE_KEY" == "Y" ]]; then
        aws ec2 delete-key-pair \
            --region $REGION \
            --key-name $KEY_NAME
        echo -e "  ${GREEN}✓ Key pair deleted${NC}"
    else
        echo "  Keeping key pair for future use."
    fi
else
    echo "  Key pair not found."
fi

echo ""

# ============================================
# 6. Check for Orphaned Volumes
# ============================================
echo -e "${BLUE}Step 6: Checking for orphaned volumes...${NC}"

AVAILABLE_VOLUMES=$(aws ec2 describe-volumes \
    --region $REGION \
    --filters "Name=status,Values=available" \
    --query "Volumes[].VolumeId" \
    --output text 2>/dev/null || echo "")

if [[ -n "$AVAILABLE_VOLUMES" ]]; then
    echo "  Found available volumes:"
    for VOL_ID in $AVAILABLE_VOLUMES; do
        VOL_SIZE=$(aws ec2 describe-volumes \
            --region $REGION \
            --volume-ids $VOL_ID \
            --query "Volumes[0].Size" \
            --output text)
        
        echo "    - $VOL_ID (${VOL_SIZE}GB)"
    done
    
    read -p "Delete these volumes? (y/N): " DELETE_VOLS
    
    if [[ "$DELETE_VOLS" == "y" || "$DELETE_VOLS" == "Y" ]]; then
        for VOL_ID in $AVAILABLE_VOLUMES; do
            aws ec2 delete-volume \
                --region $REGION \
                --volume-id $VOL_ID
            echo "      Deleted: $VOL_ID"
        done
        echo -e "  ${GREEN}✓ Volumes deleted${NC}"
    fi
else
    echo "  No orphaned volumes found."
fi

echo ""

# ============================================
# 7. Summary
# ============================================
echo -e "${GREEN}======================================"
echo "Cleanup Complete!"
echo "======================================${NC}"
echo ""
echo "Resources cleaned up:"
echo "  ✓ EC2 instances terminated"
echo "  ✓ Load Balancers deleted"
echo "  ✓ Elastic IPs released"
echo "  ✓ Security group deleted"
echo ""
echo "Verify cleanup:"
echo "  aws ec2 describe-instances --region $REGION --query 'Reservations[].Instances[].InstanceId' --output text"
echo "  aws ec2 describe-volumes --region $REGION --query 'Volumes[].VolumeId' --output text"
echo ""
echo "Check your AWS Cost Explorer to verify no unexpected charges:"
echo "  https://console.aws.amazon.com/cost-management/home"
echo ""
