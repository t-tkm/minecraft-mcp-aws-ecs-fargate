import os
from aws_cdk import (
    Stack,
    Tags,
    CfnOutput
)
from constructs import Construct
from .networking import NetworkingStack
from .storage import StorageStack
from .ec2_proxy import EC2ProxyStack
from .load_balancer import LoadBalancerStack
from .ecs import ECSStack
from .monitoring import MonitoringStack


class MinecraftStack(Stack):
    """Minecraftサーバー用のメインスタック（モジュール化）"""
    
    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)
        
        # 設定値（環境変数から読み込み）
        self.project_name = os.getenv("PROJECT_NAME", "minecraft-mcp")
        self.project_prefix = self.project_name
        self.env_name = os.getenv("ENVIRONMENT", "dev")
        self.aws_region = os.getenv("AWS_REGION", "ap-northeast-1")
        self.vpc_cidr = os.getenv("VPC_CIDR", "10.1.0.0/16")
        self.availability_zone = os.getenv("AWS_AVAILABILITY_ZONES", "ap-northeast-1a")
        # 注意: セキュリティグループでMy IP制限が自動適用されます
        self.allowed_ips = os.getenv("ALLOWED_IPS", "0.0.0.0/0").split(",")
        self.my_ip = os.getenv("MY_IP", "")
        self.ssh_public_key_path = os.getenv("SSH_PUBLIC_KEY_PATH", "~/.ssh/minecraft-proxy-key.pub")
        self.task_name = os.getenv("TASK_NAME", f"{self.project_prefix}-task")
        self.cpu = int(os.getenv("ECS_CPU", "2048"))
        self.memory = int(os.getenv("ECS_MEMORY", "8192"))
        self.container_memory = int(os.getenv("CONTAINER_MEMORY", "8192"))
        self.container_memory_reservation = int(os.getenv("CONTAINER_MEMORY_RESERVATION", "4096"))
        self.java_memory_heap = os.getenv("JAVA_MEMORY_HEAP", "6G")
        self.rcon_password = os.getenv("RCON_PASSWORD")
        if not self.rcon_password:
            raise ValueError("RCON_PASSWORD environment variable is required")
        self.minecraft_version = os.getenv("MINECRAFT_VERSION", "1.21.8")
        self.docker_image = os.getenv("DOCKER_IMAGE")  # 環境変数で指定、未指定の場合はNone
        
        # 統一された共通タグ（リソース検出用）
        self.common_tags = {
            "Project": self.project_name,
            "Environment": self.env_name,
            "ManagedBy": "cdk",
            "ResourceType": "minecraft-infrastructure",
            "StackName": construct_id,
            "CreatedBy": "minecraft-mcp-project"
        }
        
        # リソースの作成
        self._create_networking()
        self._create_storage()
        self._create_ec2_proxy()
        self._create_load_balancer()
        self._create_ecs()
        self._create_monitoring()
        
        # スタック全体にタグを適用
        self._apply_common_tags()
        
        # 出力値の作成
        self._create_outputs()
    
    def _create_networking(self):
        """ネットワークリソースの作成"""
        self.networking = NetworkingStack(
            self, "Networking",
            project_name=self.project_name,
            environment=self.env_name,
            vpc_cidr=self.vpc_cidr,
            allowed_ips=self.allowed_ips,
            my_ip=self.my_ip,
            common_tags=self.common_tags
        )
    
    def _create_storage(self):
        """ストレージリソースの作成"""
        self.storage = StorageStack(
            self, "Storage",
            project_name=self.project_name,
            environment=self.env_name,
            vpc=self.networking.vpc,
            security_group=self.networking.efs_sg,
            common_tags=self.common_tags
        )
    
    def _create_ec2_proxy(self):
        """EC2プロキシリソースの作成"""
        self.ec2_proxy = EC2ProxyStack(
            self, "EC2Proxy",
            project_name=self.project_name,
            environment=self.env_name,
            vpc=self.networking.vpc,
            security_group=self.networking.ec2_proxy_sg,
            common_tags=self.common_tags
        )
    
    def _create_load_balancer(self):
        """ロードバランサーリソースの作成"""
        self.load_balancer = LoadBalancerStack(
            self, "LoadBalancer",
            project_name=self.project_name,
            environment=self.env_name,
            vpc=self.networking.vpc,
            internal=True,
            common_tags=self.common_tags
        )
    
    def _create_ecs(self):
        """ECSリソースの作成"""
        self.ecs = ECSStack(
            self, "ECS",
            project_name=self.project_name,
            environment=self.env_name,
            aws_region=self.aws_region,
            task_name=self.task_name,
            cpu=self.cpu,
            memory=self.memory,
            container_memory=self.container_memory,
            container_memory_reservation=self.container_memory_reservation,
            java_memory_heap=self.java_memory_heap,
            rcon_password=self.rcon_password,
            efs_file_system_id=self.storage.file_system.ref,
            minecraft_version=self.minecraft_version,
            vpc=self.networking.vpc,
            security_groups=[self.networking.minecraft_sg, self.networking.efs_sg],
            docker_image=self.docker_image,
            minecraft_target_group=self.load_balancer.minecraft_tg,
            rcon_target_group=self.load_balancer.rcon_tg,
            log_retention_days=7 if self.env_name != "prod" else 30,
            common_tags=self.common_tags
        )
    
    def _create_monitoring(self):
        """モニタリングリソースの作成"""
        self.monitoring = MonitoringStack(
            self, "Monitoring",
            project_name=self.project_name,
            environment=self.env_name,
            aws_region=self.aws_region,
            cluster_name=self.ecs.cluster.cluster_name,
            service_name=self.ecs.service.service_name,
            enable_dashboard=self.env_name == "prod",
            common_tags=self.common_tags
        )
    
    def _apply_common_tags(self):
        """共通タグの適用"""
        for key, value in self.common_tags.items():
            Tags.of(self).add(key, value)
        
        # 追加のタグを適用
        Tags.of(self).add("Name", f"{self.project_name}-stack")
    
    def _create_outputs(self):
        """出力値の作成"""
        CfnOutput(
            self, "VPCId",
            value=self.networking.vpc.vpc_id,
            description="VPC ID"
        )
        
        CfnOutput(
            self, "PublicSubnetId",
            value=self.networking.vpc.public_subnets[0].subnet_id,
            description="Public Subnet ID"
        )
        
        CfnOutput(
            self, "EFSFileSystemId",
            value=self.storage.file_system.ref,
            description="EFS File System ID"
        )
        
        CfnOutput(
            self, "EC2InstanceId",
            value=self.ec2_proxy.instance.instance_id,
            description="EC2 Instance ID"
        )
        
        CfnOutput(
            self, "ElasticIP",
            value=self.ec2_proxy.eip.ref,
            description="Elastic IP"
        )
        
        CfnOutput(
            self, "LoadBalancerDNS",
            value=self.load_balancer.nlb.load_balancer_dns_name,
            description="Load Balancer DNS Name"
        )
        
        CfnOutput(
            self, "ECSClusterName",
            value=self.ecs.cluster.cluster_name,
            description="ECS Cluster Name"
        )
        
        CfnOutput(
            self, "ECSServiceName",
            value=self.ecs.service.service_name,
            description="ECS Service Name"
        )