from aws_cdk import (
    aws_ecs as ecs,
    aws_ec2 as ec2,
    aws_iam as iam,
    aws_logs as logs,
    aws_efs as efs,
    CfnOutput,
    Duration,
    RemovalPolicy,
    Tags
)
from constructs import Construct


class ECSStack(Construct):
    """ECSリソースを管理するスタック"""
    
    def __init__(self, scope: Construct, construct_id: str,
                 project_name: str, environment: str, aws_region: str,
                 task_name: str, cpu: int, memory: int,
                 container_memory: int, container_memory_reservation: int,
                 java_memory_heap: str, rcon_password: str,
                 efs_file_system_id: str, minecraft_version: str,
                 vpc: ec2.Vpc, security_groups: list[ec2.SecurityGroup],
                 minecraft_target_group,
                 rcon_target_group,
                 docker_image: str = None, log_retention_days: int = 7, common_tags: dict = None, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)
        
        self.project_name = project_name
        self.environment = environment
        self.aws_region = aws_region
        self.task_name = task_name
        self.common_tags = common_tags or {}
        
        # Dockerイメージの決定
        # 環境変数で指定されていない場合は、デフォルトのDockerHubイメージを使用
        if docker_image:
            self.docker_image = docker_image
        else:
            # デフォルトはDockerHubのMinecraftサーバーイメージ
            self.docker_image = "itzg/minecraft-server:latest"
        
        # CloudWatchロググループ
        self.log_group = logs.LogGroup(
            self, "MinecraftLogs",
            log_group_name=f"/ecs/{project_name}-{task_name}",
            retention=logs.RetentionDays.ONE_WEEK if log_retention_days == 7 else logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY
        )
        
        # ECSクラスター
        self.cluster = ecs.Cluster(
            self, "MinecraftCluster",
            cluster_name=f"{project_name}-cluster",
            vpc=vpc
        )
        
        # クラスターにタグを追加（統一されたタグ）
        for key, value in self.common_tags.items():
            Tags.of(self).add(key, value)
        Tags.of(self).add("Name", f"{project_name}-cluster")
        Tags.of(self).add("ResourceType", "minecraft-cluster")
        
        # タスク実行ロール
        self.task_execution_role = iam.Role(
            self, "TaskExecutionRole",
            assumed_by=iam.ServicePrincipal("ecs-tasks.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AmazonECSTaskExecutionRolePolicy")
            ]
        )
        
        # ECRアクセス用の権限を追加
        self.task_execution_role.add_to_policy(iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "ecr:GetAuthorizationToken",
                "ecr:BatchCheckLayerAvailability",
                "ecr:GetDownloadUrlForLayer",
                "ecr:BatchGetImage"
            ],
            resources=["*"]
        ))
        
        # タスクロール
        self.task_role = iam.Role(
            self, "TaskRole",
            assumed_by=iam.ServicePrincipal("ecs-tasks.amazonaws.com")
        )
        # EFSアクセス用の権限（Terraformと同じマネージドポリシーを使用）
        self.task_role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name("AmazonElasticFileSystemClientReadWriteAccess")
        )
        # ECS Exec用の権限も追加
        self.task_role.add_to_policy(iam.PolicyStatement(
            actions=[
                "ssmmessages:CreateControlChannel",
                "ssmmessages:CreateDataChannel",
                "ssmmessages:OpenControlChannel",
                "ssmmessages:OpenDataChannel",
                "logs:DescribeLogGroups",
                "logs:DescribeLogStreams",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            resources=["*"]
        ))
        
        # タスク定義
        self.task_definition = ecs.FargateTaskDefinition(
            self, "MinecraftTaskDefinition",
            cpu=cpu,
            memory_limit_mib=memory,
            execution_role=self.task_execution_role,
            task_role=self.task_role
        )
        
        # EFSボリューム（Terraformと同じ設定）
        self.task_definition.add_volume(
            name="data",
            efs_volume_configuration=ecs.EfsVolumeConfiguration(
                file_system_id=efs_file_system_id,
                root_directory="/",
                transit_encryption="DISABLED",
                authorization_config=ecs.AuthorizationConfig(
                    iam="DISABLED"
                )
            )
        )
        
        # コンテナ定義
        container = self.task_definition.add_container(
            f"{project_name}-container",
            image=ecs.ContainerImage.from_registry(self.docker_image),
            memory_limit_mib=container_memory,
            memory_reservation_mib=container_memory_reservation,
            logging=ecs.LogDrivers.aws_logs(
                stream_prefix=project_name,
                log_group=self.log_group
            ),
            environment={
                "EULA": "TRUE",
                "VERSION": minecraft_version,
                "TYPE": "PAPER",
                "MOTD": "Minecraft on AWS ECS",
                "DIFFICULTY": "normal",
                "GAMEMODE": "survival",
                "MAX_PLAYERS": "20",
                "RCON_PASSWORD": rcon_password,
                "ENABLE_RCON": "true",
                "RCON_PORT": "25575",
                "JAVA_OPTS": f"-Xms{java_memory_heap} -Xmx{java_memory_heap}"
            },
            port_mappings=[
                ecs.PortMapping(container_port=25565, protocol=ecs.Protocol.TCP),
                ecs.PortMapping(container_port=25575, protocol=ecs.Protocol.TCP)
            ]
        )
        
        # EFSマウント
        container.add_mount_points(
            ecs.MountPoint(
                source_volume="data",
                container_path="/data",
                read_only=False
            )
        )
        
        # ECSサービス
        self.service = ecs.FargateService(
            self, "MinecraftService",
            cluster=self.cluster,
            task_definition=self.task_definition,
            desired_count=1,
            assign_public_ip=True,
            enable_execute_command=True,
            security_groups=security_groups,
            vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PUBLIC)
        )
        
        # サービスにタグを追加（統一されたタグ）
        for key, value in self.common_tags.items():
            Tags.of(self).add(key, value)
        Tags.of(self).add("Name", f"{project_name}-service")
        Tags.of(self).add("ResourceType", "minecraft-service")
        
        # ロードバランサーとの統合
        minecraft_target_group.add_target(
            self.service.load_balancer_target(
                container_name=f"{project_name}-container",
                container_port=25565
            )
        )
        rcon_target_group.add_target(
            self.service.load_balancer_target(
                container_name=f"{project_name}-container",
                container_port=25575
            )
        )
        
        # 出力値の作成
        self._create_outputs()
    
    def _create_outputs(self):
        """出力値の作成"""
        CfnOutput(
            self, "ECSClusterName",
            value=self.cluster.cluster_name,
            description="ECS Cluster Name"
        )
        
        CfnOutput(
            self, "ECSServiceName",
            value=self.service.service_name,
            description="ECS Service Name"
        )
        
        CfnOutput(
            self, "TaskDefinitionArn",
            value=self.task_definition.task_definition_arn,
            description="Task Definition ARN"
        )
