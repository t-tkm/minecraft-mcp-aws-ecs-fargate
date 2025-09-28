from aws_cdk import (
    aws_cloudwatch as cloudwatch,
    CfnOutput
)
from constructs import Construct


class MonitoringStack(Construct):
    """モニタリングリソースを管理するスタック"""
    
    def __init__(self, scope: Construct, construct_id: str,
                 project_name: str, environment: str, aws_region: str,
                 cluster_name: str, service_name: str,
                 enable_dashboard: bool = False, common_tags: dict = None, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)
        
        self.project_name = project_name
        self.environment = environment
        self.aws_region = aws_region
        self.cluster_name = cluster_name
        self.service_name = service_name
        self.common_tags = common_tags or {}
        
        # CloudWatchダッシュボード（本番環境のみ）
        if enable_dashboard:
            self.dashboard = cloudwatch.Dashboard(
                self, "MinecraftDashboard",
                dashboard_name=f"{project_name}-dashboard"
            )
            
            # ダッシュボードウィジェットの作成
            self._create_dashboard_widgets()
        
        # 出力値の作成
        self._create_outputs()
    
    def _create_dashboard_widgets(self):
        """ダッシュボードウィジェットの作成"""
        # CPU使用率メトリクス
        cpu_metric = cloudwatch.Metric(
            namespace="AWS/ECS",
            metric_name="CPUUtilization",
            dimensions_map={
                "ServiceName": self.service_name,
                "ClusterName": self.cluster_name
            }
        )
        
        # メモリ使用率メトリクス
        memory_metric = cloudwatch.Metric(
            namespace="AWS/ECS",
            metric_name="MemoryUtilization",
            dimensions_map={
                "ServiceName": self.service_name,
                "ClusterName": self.cluster_name
            }
        )
        
        # ダッシュボードにウィジェットを追加
        self.dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="CPU Utilization",
                left=[cpu_metric],
                width=12,
                height=6
            ),
            cloudwatch.GraphWidget(
                title="Memory Utilization",
                left=[memory_metric],
                width=12,
                height=6
            )
        )
    
    def _create_outputs(self):
        """出力値の作成"""
        if hasattr(self, 'dashboard'):
            CfnOutput(
                self, "DashboardURL",
                value=f"https://{self.aws_region}.console.aws.amazon.com/cloudwatch/home?region={self.aws_region}#dashboards:name={self.project_name}-dashboard",
                description="CloudWatch Dashboard URL"
            )
