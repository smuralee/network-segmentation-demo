#!/usr/bin/env bash

GREEN="\033[1;32m"
YELLOW="\033[1;33m"

##########################################################################################
# Base Networking Resources
##########################################################################################
echo -e "${GREEN}Start building the base networking resources...."
export AWS_DEFAULT_REGION=us-east-1
cdk --app "npx ts-node bin/stacks/lib/base-network.ts" deploy --require-approval never
export AWS_DEFAULT_REGION=eu-west-1
cdk --app "npx ts-node bin/stacks/lib/base-network.ts" deploy --require-approval never
echo -e "${GREEN}Completed the base networking resources...."

##########################################################################################
# Transit Gateway Inter-region Peering
##########################################################################################
echo -e "${GREEN}Start peering the transit gateways..."
echo -e "${GREEN}Initiating peering..."
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_DEFAULT_REGION=eu-west-1
export PEER_TGW_ID=$(aws cloudformation describe-stacks --stack-name NetworkSegmentationDemo --query 'Stacks[*].Outputs[?ExportName==`TransitGatewayId`].OutputValue' --output text)
export AWS_DEFAULT_REGION=us-east-1
export TGW_ID=$(aws cloudformation describe-stacks --stack-name NetworkSegmentationDemo --query 'Stacks[*].Outputs[?ExportName==`TransitGatewayId`].OutputValue' --output text)
export PEER_REGION=eu-west-1
aws ec2 create-transit-gateway-peering-attachment \
    --transit-gateway-id $TGW_ID \
    --peer-transit-gateway-id $PEER_TGW_ID \
    --peer-account-id $AWS_ACCOUNT_ID \
    --peer-region $PEER_REGION \
    --tag-specifications 'ResourceType=transit-gateway-attachment,Tags=[{Key=Name,Value=TGWPeering}]'
PEER_STATE=$(aws ec2 describe-transit-gateway-peering-attachments --filters Name=transit-gateway-id,Values=$TGW_ID Name=state,Values=initiatingRequest,pendingAcceptance,pending,available --query 'TransitGatewayPeeringAttachments[*].State' --output text | xargs)

# Wait till the attachment status is pendingAcceptance - 10 seconds delay before each check
while [ "$PEER_STATE" != "pendingAcceptance" ];
do
   sleep 10
   PEER_STATE=$(aws ec2 describe-transit-gateway-peering-attachments --filters Name=transit-gateway-id,Values=$TGW_ID Name=state,Values=initiatingRequest,pendingAcceptance,pending,available --query 'TransitGatewayPeeringAttachments[*].State' --output text | xargs)
   echo -e "${YELLOW}Awaiting pendingAcceptance status....Current status: ${PEER_STATE}"
done

echo -e "${GREEN}Initiating acceptance..."
export AWS_DEFAULT_REGION=eu-west-1
export PEER_ID=$(aws ec2 describe-transit-gateway-peering-attachments --filters Name=state,Values=initiatingRequest,pendingAcceptance,pending,available --query 'TransitGatewayPeeringAttachments[*].TransitGatewayAttachmentId' --output text | xargs)
aws ec2 accept-transit-gateway-peering-attachment \
    --transit-gateway-attachment-id $PEER_ID \
    --region $AWS_DEFAULT_REGION

export AWS_DEFAULT_REGION=us-east-1
PEER_STATE=$(aws ec2 describe-transit-gateway-peering-attachments --filters Name=transit-gateway-id,Values=$TGW_ID Name=state,Values=initiatingRequest,pendingAcceptance,pending,available --query 'TransitGatewayPeeringAttachments[*].State' --output text | xargs)

# Wait till the attachment status is available - 10 seconds delay before each check
while [ "$PEER_STATE" != "available" ];
do
   sleep 10
   PEER_STATE=$(aws ec2 describe-transit-gateway-peering-attachments --filters Name=transit-gateway-id,Values=$TGW_ID Name=state,Values=initiatingRequest,pendingAcceptance,pending,available --query 'TransitGatewayPeeringAttachments[*].State' --output text | xargs)
   echo -e "${YELLOW}Awaiting available status....Current status: ${PEER_STATE}"
done

echo -e "${GREEN}Completed acceptance..."
echo -e "${GREEN}Completed transit gateway inter-region peering..."

##########################################################################################
# Transit Gateway Routing
##########################################################################################

echo -e "${GREEN}Start building the transit gateway routing...."

export AWS_DEFAULT_REGION=us-east-1
export TGW_ID=$(aws cloudformation describe-stacks --stack-name NetworkSegmentationDemo --query 'Stacks[*].Outputs[?ExportName==`TransitGatewayId`].OutputValue' --output text)
export DEVELOPMENT_VPC_ATTACHMENT_ID=$(aws cloudformation describe-stacks --stack-name NetworkSegmentationDemo --query 'Stacks[*].Outputs[?ExportName==`DevelopmentTGWAttachmentId`].OutputValue' --output text)
export DEVELOPMENT_VPC_ROUTE_TABLE_ID=$(aws cloudformation describe-stacks --stack-name NetworkSegmentationDemo --query 'Stacks[*].Outputs[?ExportName==`DevelopmentTGWRouteTableId`].OutputValue' --output text)
export PRODUCTION_VPC_ATTACHMENT_ID=$(aws cloudformation describe-stacks --stack-name NetworkSegmentationDemo --query 'Stacks[*].Outputs[?ExportName==`ProductionTGWAttachmentId`].OutputValue' --output text)
export PRODUCTION_VPC_ROUTE_TABLE_ID=$(aws cloudformation describe-stacks --stack-name NetworkSegmentationDemo --query 'Stacks[*].Outputs[?ExportName==`ProductionTGWRouteTableId`].OutputValue' --output text)
export PEER_ATTACHMENT_ID=$(aws ec2 describe-transit-gateway-attachments --filters Name=resource-type,Values=peering Name=transit-gateway-id,Values=$TGW_ID Name=state,Values=available --query 'TransitGatewayAttachments[*].TransitGatewayAttachmentId' --output text)
export VPN_ATTACHMENT_ID=$(aws ec2 describe-transit-gateway-attachments --filters Name=resource-type,Values=vpn Name=transit-gateway-id,Values=$TGW_ID Name=state,Values=available --query 'TransitGatewayAttachments[*].TransitGatewayAttachmentId' --output text)

cdk --app "npx ts-node bin/stacks/lib/transit-gateway-routing.ts" deploy --require-approval never

export AWS_DEFAULT_REGION=eu-west-1
export TGW_ID=$(aws cloudformation describe-stacks --stack-name NetworkSegmentationDemo --query 'Stacks[*].Outputs[?ExportName==`TransitGatewayId`].OutputValue' --output text)
export DEVELOPMENT_VPC_ATTACHMENT_ID=$(aws cloudformation describe-stacks --stack-name NetworkSegmentationDemo --query 'Stacks[*].Outputs[?ExportName==`DevelopmentTGWAttachmentId`].OutputValue' --output text)
export DEVELOPMENT_VPC_ROUTE_TABLE_ID=$(aws cloudformation describe-stacks --stack-name NetworkSegmentationDemo --query 'Stacks[*].Outputs[?ExportName==`DevelopmentTGWRouteTableId`].OutputValue' --output text)
export PRODUCTION_VPC_ATTACHMENT_ID=$(aws cloudformation describe-stacks --stack-name NetworkSegmentationDemo --query 'Stacks[*].Outputs[?ExportName==`ProductionTGWAttachmentId`].OutputValue' --output text)
export PRODUCTION_VPC_ROUTE_TABLE_ID=$(aws cloudformation describe-stacks --stack-name NetworkSegmentationDemo --query 'Stacks[*].Outputs[?ExportName==`ProductionTGWRouteTableId`].OutputValue' --output text)
export PEER_ATTACHMENT_ID=$(aws ec2 describe-transit-gateway-attachments --filters Name=resource-type,Values=peering Name=transit-gateway-id,Values=$TGW_ID Name=state,Values=available --query 'TransitGatewayAttachments[*].TransitGatewayAttachmentId' --output text)
export VPN_ATTACHMENT_ID=$(aws ec2 describe-transit-gateway-attachments --filters Name=resource-type,Values=vpn Name=transit-gateway-id,Values=$TGW_ID Name=state,Values=available --query 'TransitGatewayAttachments[*].TransitGatewayAttachmentId' --output text)

cdk --app "npx ts-node bin/stacks/lib/transit-gateway-routing.ts" deploy --require-approval never

echo -e "${GREEN}Completed the transit gateway routing...."

##########################################################################################
# Global Network
##########################################################################################

echo -e "${GREEN}Start building the global network...."

export AWS_DEFAULT_REGION=us-east-1
export US_TGW_ID=$(aws cloudformation describe-stacks --stack-name NetworkSegmentationDemo --query 'Stacks[*].Outputs[?ExportName==`TransitGatewayId`].OutputValue' --output text)
export US_TGW_ARN=$(aws ec2 describe-transit-gateways --transit-gateway-ids $US_TGW_ID --query 'TransitGateways[*].TransitGatewayArn' --output text)
export AWS_DEFAULT_REGION=eu-west-1
export EU_TGW_ID=$(aws cloudformation describe-stacks --stack-name NetworkSegmentationDemo --query 'Stacks[*].Outputs[?ExportName==`TransitGatewayId`].OutputValue' --output text)
export EU_TGW_ARN=$(aws ec2 describe-transit-gateways --transit-gateway-ids $EU_TGW_ID --query 'TransitGateways[*].TransitGatewayArn' --output text)
export AWS_DEFAULT_REGION=us-east-1

cdk --app "npx ts-node bin/stacks/lib/global-network.ts" deploy --require-approval never

echo -e "${GREEN}Completed the global network...."
