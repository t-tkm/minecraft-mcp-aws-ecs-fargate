from aws_cdk import (
    aws_ec2 as ec2,
    aws_iam as iam,
    CfnOutput,
    Tags
)
from constructs import Construct


class EC2ProxyStack(Construct):
    """EC2プロキシリソースを管理するスタック"""
    
    def __init__(self, scope: Construct, construct_id: str,
                 project_name: str, environment: str, vpc: ec2.Vpc,
                 security_group: ec2.SecurityGroup, common_tags: dict = None, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)
        
        self.project_name = project_name
        self.environment = environment
        self.common_tags = common_tags or {}
        
        # キーペア
        self.key_pair = ec2.KeyPair(
            self, "MinecraftProxyKeyPair",
            key_pair_name=f"{project_name}-proxy-key"
        )
        
        # IAMロール
        self.ec2_role = iam.Role(
            self, "EC2ProxyRole",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonSSMManagedInstanceCore")
            ]
        )
        
        # インスタンスプロファイル
        self.instance_profile = iam.CfnInstanceProfile(
            self, "EC2ProxyInstanceProfile",
            roles=[self.ec2_role.role_name]
        )
        
        # EC2インスタンス
        self.instance = ec2.Instance(
            self, "MinecraftProxy",
            vpc=vpc,
            instance_type=ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MICRO),
            machine_image=ec2.MachineImage.latest_amazon_linux2(),
            security_group=security_group,
            key_pair=self.key_pair,
            role=self.ec2_role,
            user_data=ec2.UserData.custom("""
#!/bin/bash
yum update -y
yum install -y htop
echo "EC2 proxy instance ready for Session Manager port forwarding"
            """)
        )
        
        # インスタンスにタグを追加（統一されたタグ）
        for key, value in self.common_tags.items():
            Tags.of(self.instance).add(key, value)
        Tags.of(self.instance).add("Name", f"{project_name}-proxy")
        Tags.of(self.instance).add("ResourceType", "minecraft-proxy")
        
        # Elastic IP
        self.eip = ec2.CfnEIP(
            self, "MinecraftProxyEIP",
            instance_id=self.instance.instance_id,
            domain="vpc",
            tags=[
                {"key": "Name", "value": f"{project_name}-proxy-eip"},
                {"key": "Environment", "value": environment},
                {"key": "Project", "value": project_name}
            ]
        )
        
        # 出力値の作成
        self._create_outputs()
    
    def _create_outputs(self):
        """出力値の作成"""
        CfnOutput(
            self, "EC2InstanceId",
            value=self.instance.instance_id,
            description="EC2 Instance ID"
        )
        
        CfnOutput(
            self, "ElasticIP",
            value=self.eip.ref,
            description="Elastic IP"
        )
        
        CfnOutput(
            self, "KeyPairName",
            value=self.key_pair.key_pair_name,
            description="Key Pair Name"
        )
