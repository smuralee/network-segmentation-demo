#!/usr/bin/env bash

GREEN="\033[1;32m"
YELLOW="\033[1;33m"

echo -e "${GREEN}Start cleanup..."
##########################################################################################
# Delete the TGW peering
##########################################################################################
echo -e "${GREEN}Deleting the peering attachment..."
export AWS_DEFAULT_REGION=us-east-1
export TGW_ID=$(aws cloudformation describe-stacks --stack-name NetworkSegmentationDemo --query 'Stacks[*].Outputs[?ExportName==`TransitGatewayId`].OutputValue' --output text)
export PEER_ATTACHMENT_ID=$(aws ec2 describe-transit-gateway-attachments --filters Name=resource-type,Values=peering Name=transit-gateway-id,Values=$TGW_ID Name=state,Values=available --query 'TransitGatewayAttachments[*].TransitGatewayAttachmentId' --output text)
aws ec2 delete-transit-gateway-peering-attachment \
    --transit-gateway-attachment-id $PEER_ATTACHMENT_ID \
    --region $AWS_DEFAULT_REGION

PEER_STATE=$(aws ec2 describe-transit-gateway-peering-attachments --filters Name=transit-gateway-id,Values=$TGW_ID Name=state,Values=deleting,deleted --query 'TransitGatewayPeeringAttachments[*].State' --output text | xargs)

# Wait till the attachment status is deleted - 10 seconds delay before each check
while [ "$PEER_STATE" != "deleted" ];
do
   sleep 10
   PEER_STATE=$(aws ec2 describe-transit-gateway-peering-attachments --filters Name=transit-gateway-id,Values=$TGW_ID Name=state,Values=deleting,deleted --query 'TransitGatewayPeeringAttachments[*].State' --output text | xargs)
   echo -e "${YELLOW}Awaiting deleted status....Current status: ${PEER_STATE}"
done

echo -e "${GREEN}Peering attachment deleted..."
##########################################################################################
# Delete the CDK stacks
##########################################################################################

echo -e "${GREEN}Deleting CDK stacks..."

# Assign the variable
STACK_STATE="DELETE_COMPLETE"

export AWS_DEFAULT_REGION=us-east-1
declare -a us_stacks=("NetworkSegmentationGlobalManager" "NetworkSegmentationRouting" "NetworkSegmentationDemo")

for stack in "${us_stacks[@]}"
do
  echo -e "${GREEN}Deleting $stack stack..."
  aws cloudformation delete-stack --stack-name $stack --region $AWS_DEFAULT_REGION
  STACK_STATE=$(aws cloudformation describe-stacks --stack-name $stack --region $AWS_DEFAULT_REGION --query 'Stacks[*].StackStatus' --output text || echo "DELETE_COMPLETE")
  # Wait till the stack status is DELETE_COMPLETE
  while [ "$STACK_STATE" != "DELETE_COMPLETE" ];
  do
    sleep 10
    if [ "$STACK_STATE" == "DELETE_FAILED" ]
    then
      echo -e "${GREEN}Delete failed...retrying..."
      aws cloudformation delete-stack --stack-name $stack --region $AWS_DEFAULT_REGION
    fi
    STACK_STATE=$(aws cloudformation describe-stacks --stack-name $stack --region $AWS_DEFAULT_REGION --query 'Stacks[*].StackStatus' --output text || echo "DELETE_COMPLETE")
    echo -e "${YELLOW}Awaiting DELETE_COMPLETE status....Current status: ${STACK_STATE}"
  done
done

export AWS_DEFAULT_REGION=eu-west-1
declare -a eu_stacks=("NetworkSegmentationRouting" "NetworkSegmentationDemo")

for stack in "${eu_stacks[@]}"
do
  echo -e "${GREEN}Deleting $stack stack..."
  aws cloudformation delete-stack --stack-name $stack --region $AWS_DEFAULT_REGION
  STACK_STATE=$(aws cloudformation describe-stacks --stack-name $stack --region $AWS_DEFAULT_REGION --query 'Stacks[*].StackStatus' --output text || echo "DELETE_COMPLETE")
  # Wait till the stack status is DELETE_COMPLETE
  while [ "$STACK_STATE" != "DELETE_COMPLETE" ];
  do
    sleep 10
    if [ "$STACK_STATE" == "DELETE_FAILED" ]
    then
      echo -e "${GREEN}Delete failed...retrying..."
      aws cloudformation delete-stack --stack-name $stack --region $AWS_DEFAULT_REGION
    fi
    STACK_STATE=$(aws cloudformation describe-stacks --stack-name $stack --region $AWS_DEFAULT_REGION --query 'Stacks[*].StackStatus' --output text || echo "DELETE_COMPLETE")
    echo -e "${YELLOW}Awaiting DELETE_COMPLETE status....Current status: ${STACK_STATE}"
  done
done

echo -e "${YELLOW}You can ignore the (ValidationError) when calling the DescribeStacks operation..."
echo -e "${GREEN}Cleanup completed..."
