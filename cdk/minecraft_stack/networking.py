import requests
from aws_cdk import (
    aws_ec2 as ec2,
    CfnOutput,
    Tags
)
from constructs import Construct


class NetworkingStack(Construct):
    """ネットワークリソースを管理するスタック"""
    
    def __init__(self, scope: Construct, construct_id: str,
                 project_name: str, environment: str, vpc_cidr: str,
                 allowed_ips: list[str], my_ip: str = "", common_tags: dict = None, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)
        
        self.project_name = project_name
        self.environment = environment
        self.allowed_ips = allowed_ips
        self.vpc_cidr = vpc_cidr
        self.manual_my_ip = my_ip
        self.common_tags = common_tags or {}
        
        # 現在のIPアドレスを取得（手動設定されていない場合のみ）
        self.my_ip = self._get_my_ip()
        
        # VPC
        self.vpc = ec2.Vpc(
            self, "MinecraftVPC",
            ip_addresses=ec2.IpAddresses.cidr(vpc_cidr),
            max_azs=1,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="Public",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24
                )
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True
        )
        
        # セキュリティグループ
        self.minecraft_sg = ec2.SecurityGroup(
            self, "MinecraftSecurityGroup",
            vpc=self.vpc,
            description="Minecraft server security group",
            allow_all_outbound=True
        )
        
        self.ec2_proxy_sg = ec2.SecurityGroup(
            self, "EC2ProxySecurityGroup",
            vpc=self.vpc,
            description="EC2 proxy security group",
            allow_all_outbound=True
        )
        
        self.efs_sg = ec2.SecurityGroup(
            self, "EFSSecurityGroup",
            vpc=self.vpc,
            description="EFS security group",
            allow_all_outbound=True
        )
        
        # セキュリティグループルール
        self._create_security_group_rules()
        
        # 出力値の作成
        self._create_outputs()
    
    def _get_my_ip(self) -> str:
        """現在のIPアドレスを取得（手動設定されていない場合のみ）"""
        if self.manual_my_ip:
            return self.manual_my_ip
        
        try:
            response = requests.get("https://ipv4.icanhazip.com", timeout=10)
            return response.text.strip() + "/32"
        except Exception as e:
            print(f"Warning: Could not fetch current IP address: {e}")
            # フォールバック: 最初のallowed_ipsを使用
            return self.allowed_ips[0] if self.allowed_ips else "0.0.0.0/0"
    
    def _create_security_group_rules(self):
        """セキュリティグループルールの作成"""
        # Minecraftサーバー用ルール - VPC内からのアクセス（NLBヘルスチェック用）
        self.minecraft_sg.add_ingress_rule(
            ec2.Peer.ipv4(self.vpc_cidr),
            ec2.Port.tcp(25565),
            "Minecraft port from VPC"
        )
        self.minecraft_sg.add_ingress_rule(
            ec2.Peer.ipv4(self.vpc_cidr),
            ec2.Port.tcp(25575),
            "RCON port from VPC"
        )
        
        # Minecraftサーバー用ルール - VPC内からのアクセスのみ（NLB経由）
        # 直接的な外部アクセスは許可しない（NLB経由のみ）
        
        # EC2プロキシ用ルール - HTTPSアクセス（MyIPからのみ）
        self.ec2_proxy_sg.add_ingress_rule(
            ec2.Peer.ipv4(self.my_ip),
            ec2.Port.tcp(443),
            "HTTPS access for port forwarding from my IP"
        )
        
        # EFS用ルール - ECS TaskのセキュリティグループからのNFSアクセスのみ許可
        self.efs_sg.add_ingress_rule(
            ec2.Peer.security_group_id(self.minecraft_sg.security_group_id),
            ec2.Port.tcp(2049),
            "EFS NFS from ECS tasks"
        )
    
    def _create_outputs(self):
        """出力値の作成"""
        CfnOutput(
            self, "VPCId",
            value=self.vpc.vpc_id,
            description="VPC ID"
        )
        
        CfnOutput(
            self, "PublicSubnetId",
            value=self.vpc.public_subnets[0].subnet_id,
            description="Public Subnet ID"
        )
        
        CfnOutput(
            self, "MinecraftSecurityGroupId",
            value=self.minecraft_sg.security_group_id,
            description="Minecraft Security Group ID"
        )
        
        CfnOutput(
            self, "EC2ProxySecurityGroupId",
            value=self.ec2_proxy_sg.security_group_id,
            description="EC2 Proxy Security Group ID"
        )
        
        CfnOutput(
            self, "EFSSecurityGroupId",
            value=self.efs_sg.security_group_id,
            description="EFS Security Group ID"
        )
