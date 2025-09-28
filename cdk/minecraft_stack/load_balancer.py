from aws_cdk import (
    aws_elasticloadbalancingv2 as elbv2,
    aws_ec2 as ec2,
    CfnOutput,
    Duration,
    Tags
)
from constructs import Construct


class LoadBalancerStack(Construct):
    """ロードバランサーリソースを管理するスタック"""
    
    def __init__(self, scope: Construct, construct_id: str,
                 project_name: str, environment: str, vpc: ec2.Vpc,
                 internal: bool = True, common_tags: dict = None, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)
        
        self.project_name = project_name
        self.environment = environment
        self.common_tags = common_tags or {}
        
        # ネットワークロードバランサー
        self.nlb = elbv2.NetworkLoadBalancer(
            self, "MinecraftLoadBalancer",
            vpc=vpc,
            internet_facing=not internal,
            load_balancer_name=f"{project_name}-lb"
        )
        
        # ロードバランサーにタグを追加（統一されたタグ）
        for key, value in self.common_tags.items():
            Tags.of(self.nlb).add(key, value)
        Tags.of(self.nlb).add("Name", f"{project_name}-lb")
        Tags.of(self.nlb).add("ResourceType", "minecraft-loadbalancer")
        
        # Minecraft用ターゲットグループ（Terraformと同じ設定）
        self.minecraft_tg = elbv2.NetworkTargetGroup(
            self, "MinecraftTargetGroup",
            vpc=vpc,
            port=25565,
            protocol=elbv2.Protocol.TCP,
            target_type=elbv2.TargetType.IP,
            deregistration_delay=Duration.seconds(30),  # Terraformと同じ
            health_check=elbv2.HealthCheck(
                enabled=True,
                protocol=elbv2.Protocol.TCP,
                port="traffic-port",  # Terraformと同じ
                healthy_threshold_count=2,        # Terraformと同じ
                unhealthy_threshold_count=2,      # Terraformと同じ
                interval=Duration.seconds(60),    # Terraformと同じ
            )
        )
        
        # RCON用ターゲットグループ（Terraformと同じ設定）
        self.rcon_tg = elbv2.NetworkTargetGroup(
            self, "RCONTargetGroup",
            vpc=vpc,
            port=25575,
            protocol=elbv2.Protocol.TCP,
            target_type=elbv2.TargetType.IP,
            deregistration_delay=Duration.seconds(30),  # Terraformと同じ
            health_check=elbv2.HealthCheck(
                enabled=True,
                protocol=elbv2.Protocol.TCP,
                port="traffic-port",  # Terraformと同じ
                healthy_threshold_count=2,        # Terraformと同じ
                unhealthy_threshold_count=2,      # Terraformと同じ
                interval=Duration.seconds(60),    # Terraformと同じ
            )
        )
        
        # リスナー
        self.minecraft_listener = self.nlb.add_listener(
            "MinecraftListener",
            port=25565,
            protocol=elbv2.Protocol.TCP,
            default_target_groups=[self.minecraft_tg]
        )
        
        self.rcon_listener = self.nlb.add_listener(
            "RCONListener",
            port=25575,
            protocol=elbv2.Protocol.TCP,
            default_target_groups=[self.rcon_tg]
        )
        
        # 出力値の作成
        self._create_outputs()
    
    def _create_outputs(self):
        """出力値の作成"""
        CfnOutput(
            self, "LoadBalancerDNS",
            value=self.nlb.load_balancer_dns_name,
            description="Load Balancer DNS Name"
        )
        
        CfnOutput(
            self, "LoadBalancerArn",
            value=self.nlb.load_balancer_arn,
            description="Load Balancer ARN"
        )
        
        CfnOutput(
            self, "MinecraftTargetGroupArn",
            value=self.minecraft_tg.target_group_arn,
            description="Minecraft Target Group ARN"
        )
        
        CfnOutput(
            self, "RCONTargetGroupArn",
            value=self.rcon_tg.target_group_arn,
            description="RCON Target Group ARN"
        )
