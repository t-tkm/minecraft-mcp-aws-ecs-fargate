from aws_cdk import (
    aws_efs as efs,
    aws_ec2 as ec2,
    CfnOutput,
    RemovalPolicy
)
from constructs import Construct


class StorageStack(Construct):
    """ストレージリソースを管理するスタック"""
    
    def __init__(self, scope: Construct, construct_id: str,
                 project_name: str, environment: str, vpc: ec2.Vpc,
                 security_group: ec2.SecurityGroup, common_tags: dict = None, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)
        
        self.project_name = project_name
        self.environment = environment
        self.common_tags = common_tags or {}
        
        # EFSファイルシステム（低レベルコンストラクトでポリシーなし）
        self.file_system = efs.CfnFileSystem(
            self, "MinecraftDataEFS",
            performance_mode="generalPurpose",
            throughput_mode="bursting",
            encrypted=True,  # Terraformと同じく暗号化有効
            file_system_tags=[
                {"key": "Name", "value": f"{project_name}-data"},
                {"key": "Environment", "value": environment},
                {"key": "Project", "value": project_name},
                {"key": "ManagedBy", "value": "cdk"},
                {"key": "ResourceType", "value": "minecraft-storage"}
            ]
        )

        # マウントターゲットを手動で作成（手動SGを使用）
        for i, subnet in enumerate(vpc.public_subnets):
            efs.CfnMountTarget(
                self, f"MinecraftDataMountTarget{i}",
                file_system_id=self.file_system.ref,
                subnet_id=subnet.subnet_id,
                security_groups=[security_group.security_group_id]  # 手動SGを使用
            )
        
        # 出力値の作成
        self._create_outputs()
    
    def _create_outputs(self):
        """出力値の作成"""
        CfnOutput(
            self, "EFSFileSystemId",
            value=self.file_system.ref,
            description="EFS File System ID"
        )
        
        CfnOutput(
            self, "EFSFileSystemArn",
            value=self.file_system.attr_arn,
            description="EFS File System ARN"
        )
