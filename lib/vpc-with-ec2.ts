import * as cdk from "@aws-cdk/core";
import {CfnOutput} from "@aws-cdk/core";
import {
    AmazonLinuxCpuType,
    AmazonLinuxGeneration,
    CfnTransitGateway,
    CfnTransitGatewayAttachment,
    CfnTransitGatewayRouteTable,
    InstanceClass,
    InstanceSize,
    InstanceType,
    InterfaceVpcEndpointAwsService,
    IVpc,
    Port,
    SecurityGroup,
    SubnetType
} from "@aws-cdk/aws-ec2";
import {IRole} from "@aws-cdk/aws-iam";
import ec2 = require('@aws-cdk/aws-ec2');

export interface VpcWithEc2Props {
    readonly prefix?: string;
    readonly cidr?: string;
    readonly cidrMask?: number;
    readonly transitGateway?: CfnTransitGateway;
    readonly ec2Role?: IRole;
}

export class VpcWithEc2 extends cdk.Construct {

    public readonly vpc: IVpc;
    public readonly securityGroup: SecurityGroup;
    public readonly subnetIds: string[] = [];
    public readonly cfnTransitGatewayAttachment: CfnTransitGatewayAttachment
    public readonly cfnTransitGatewayRouteTable: CfnTransitGatewayRouteTable

    constructor(scope: cdk.Construct, id: string, props: VpcWithEc2Props = {}) {

        super(scope, id);

        // Create the VPC with ISOLATED subnets
        this.vpc = new ec2.Vpc(this, props.prefix!.concat('-VPC').toString(), {
            cidr: props.cidr,
            maxAzs: 3,
            subnetConfiguration: [
                {
                    cidrMask: props.cidrMask,
                    name: props.prefix!.concat('-VPC | Isolated'),
                    subnetType: SubnetType.ISOLATED
                }]
        });

        // Populate the subnetIDs
        this.vpc.isolatedSubnets.forEach(subnet => this.subnetIds.push(subnet.subnetId));

        // SecurityGroup for the EC2 instance
        this.securityGroup = new ec2.SecurityGroup(this, props.prefix!.concat('-SG').toString(), {
            vpc: this.vpc,
            description: "Allow ICMP ping and HTTPS"
        });
        this.securityGroup.addIngressRule(ec2.Peer.anyIpv4(), Port.icmpPing(), "Allow ICMP");
        this.securityGroup.addIngressRule(ec2.Peer.anyIpv4(), Port.tcp(443), "Allow HTTPS");

        // Create the VPC Interface Endpoints
        new ec2.InterfaceVpcEndpoint(this, props.prefix!.concat('-SSM').toString(), {
            service: InterfaceVpcEndpointAwsService.SSM,
            vpc: this.vpc,
            privateDnsEnabled: true,
            securityGroups: [this.securityGroup],
            subnets: this.vpc.selectSubnets({
                subnetType: SubnetType.ISOLATED
            })
        });
        new ec2.InterfaceVpcEndpoint(this, props.prefix!.concat('-SSM_MESSAGES').toString(), {
            service: InterfaceVpcEndpointAwsService.SSM_MESSAGES,
            vpc: this.vpc,
            privateDnsEnabled: true,
            securityGroups: [this.securityGroup],
            subnets: this.vpc.selectSubnets({
                subnetType: SubnetType.ISOLATED
            })
        });
        new ec2.InterfaceVpcEndpoint(this, props.prefix!.concat('-EC2').toString(), {
            service: InterfaceVpcEndpointAwsService.EC2,
            vpc: this.vpc,
            privateDnsEnabled: true,
            securityGroups: [this.securityGroup],
            subnets: this.vpc.selectSubnets({
                subnetType: SubnetType.ISOLATED
            })
        });
        new ec2.InterfaceVpcEndpoint(this, props.prefix!.concat('-EC2_MESSAGES').toString(), {
            service: InterfaceVpcEndpointAwsService.EC2_MESSAGES,
            vpc: this.vpc,
            privateDnsEnabled: true,
            securityGroups: [this.securityGroup],
            subnets: this.vpc.selectSubnets({
                subnetType: SubnetType.ISOLATED
            })
        });

        // Create a EC2 instance
        new ec2.Instance(this, props.prefix!.concat("-Instance").toString(), {
            instanceType: InstanceType.of(InstanceClass.T2, InstanceSize.MICRO),
            role: props.ec2Role,
            vpc: this.vpc,
            securityGroup: this.securityGroup,
            machineImage: new ec2.AmazonLinuxImage({
                cpuType: AmazonLinuxCpuType.X86_64,
                generation: AmazonLinuxGeneration.AMAZON_LINUX_2
            })
        });

        // Create a transit gateway route table
        this.cfnTransitGatewayRouteTable = new ec2.CfnTransitGatewayRouteTable(this, props.prefix!.concat("-RouteTable").toString(), {
            transitGatewayId: props.transitGateway!.ref,
            tags: [
                {
                    key: "Name",
                    value: props.prefix!.concat("-RouteTable").toString()
                }
            ]
        });

        // // Create a transit gateway attachment
        this.cfnTransitGatewayAttachment = new ec2.CfnTransitGatewayAttachment(this, props.prefix!.concat("-Attachment").toString(), {
            transitGatewayId: props.transitGateway!.ref,
            vpcId: this.vpc.vpcId,
            subnetIds: this.subnetIds,
            tags: [
                {
                    key: "Name",
                    value: props.prefix!.concat("-Attachment").toString()
                }
            ]
        });

        // Create a transit gateway association
        const cfnTransitGatewayRouteTableAssociation = new ec2.CfnTransitGatewayRouteTableAssociation(this, props.prefix!.concat("-RouteTableAssociation").toString(), {
            transitGatewayRouteTableId: this.cfnTransitGatewayRouteTable.ref,
            transitGatewayAttachmentId: this.cfnTransitGatewayAttachment.ref
        });
        cfnTransitGatewayRouteTableAssociation.node.addDependency(this.cfnTransitGatewayRouteTable);
        cfnTransitGatewayRouteTableAssociation.node.addDependency(this.cfnTransitGatewayAttachment);

        // Create a transit gateway propagation
        const cfnTransitGatewayRouteTablePropagation = new ec2.CfnTransitGatewayRouteTablePropagation(this, props.prefix!.concat("-RouteTablePropagation").toString(), {
            transitGatewayRouteTableId: this.cfnTransitGatewayRouteTable.ref,
            transitGatewayAttachmentId: this.cfnTransitGatewayAttachment.ref
        });
        cfnTransitGatewayRouteTablePropagation.node.addDependency(this.cfnTransitGatewayRouteTable);
        cfnTransitGatewayRouteTablePropagation.node.addDependency(this.cfnTransitGatewayAttachment);

        //Outputs
        new CfnOutput(this, props.prefix!.concat("-VPCId").toString(), {
            description: "VPCId for the environment",
            exportName: props.prefix!.concat("VPCId").toString(),
            value: this.vpc.vpcId
        });
        new CfnOutput(this, props.prefix!.concat("-TGWAttachmentId").toString(), {
            description: "TGWAttachmentId for the VPC",
            exportName: props.prefix!.concat("TGWAttachmentId").toString(),
            value: this.cfnTransitGatewayAttachment.ref
        });
        new CfnOutput(this, props.prefix!.concat("-TGWRouteTableId").toString(), {
            description: "TGWRouteTableId for the VPC",
            exportName: props.prefix!.concat("TGWRouteTableId").toString(),
            value: this.cfnTransitGatewayRouteTable.ref
        });
    }
}
