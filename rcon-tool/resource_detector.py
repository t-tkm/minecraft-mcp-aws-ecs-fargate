#!/usr/bin/env python3
"""
Minecraft MCP Project - 統一リソース検出ライブラリ
TerraformとCDKで構築されたリソースを環境ベースで検出する
"""

import os
import json
import subprocess
import logging
import shutil
from typing import Optional, Dict, List, Tuple
from dataclasses import dataclass
from enum import Enum

# ログ設定
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class DetectionMode(Enum):
    """リソース検出モード"""
    AUTO = "auto"      # 環境変数 → タグ → 命名規則の順で検出
    ENV = "env"        # 環境変数のみ
    TAGS = "tags"      # タグベース検索のみ
    NAMING = "naming"  # 命名規則ベース検索のみ

@dataclass
class ResourceConfig:
    """検出されたリソース設定"""
    cluster_name: str
    service_name: str
    container_name: str
    task_arn: str
    ec2_instance_id: str
    nlb_dns_name: str
    detection_mode: str
    project_name: str
    environment: str

class ResourceDetector:
    """統一リソース検出クラス"""
    
    def __init__(self, environment: str, project_name: str, aws_region: str):
        self.environment = environment
        self.project_name = project_name
        self.aws_region = aws_region
        self.detection_mode = DetectionMode(os.getenv("RESOURCE_DETECTION_MODE", "auto"))
        
        # AWS CLIのパスを取得
        self.aws_cli_path = self._get_aws_cli_path()
        
        # 共通タグ（TerraformとCDKで統一）
        self.common_tags = {
            "Project": project_name,
            "Environment": environment
        }
        
        logger.info(f"ResourceDetector initialized: env={environment}, project={project_name}, region={aws_region}")
        logger.info(f"AWS CLI path: {self.aws_cli_path}")
    
    def _get_aws_cli_path(self) -> str:
        """AWS CLIのフルパスを取得"""
        # まずwhichコマンドでAWS CLIのパスを取得
        try:
            result = subprocess.run(["which", "aws"], capture_output=True, text=True, check=True)
            aws_path = result.stdout.strip()
            if aws_path and os.path.exists(aws_path):
                return aws_path
        except subprocess.CalledProcessError:
            pass
        
        # whichで見つからない場合は、一般的なパスを試す
        common_paths = [
            "/usr/local/bin/aws",
            "/opt/homebrew/bin/aws",
            "/usr/bin/aws",
            shutil.which("aws")
        ]
        
        for path in common_paths:
            if path and os.path.exists(path):
                return path
        
        # 最後の手段として"aws"を返す（PATHに含まれている場合）
        return "aws"
    
    def detect_all_resources(self) -> ResourceConfig:
        """すべてのリソースを検出して設定を返す"""
        logger.info("Starting resource detection...")
        
        cluster_name = self._detect_ecs_cluster()
        service_name = self._detect_ecs_service(cluster_name)
        task_arn = self._detect_task_arn(cluster_name, service_name)
        container_name = self._detect_container_name(cluster_name, task_arn)
        ec2_instance_id = self._detect_ec2_instance()
        nlb_dns_name = self._detect_nlb_dns()
        
        config = ResourceConfig(
            cluster_name=cluster_name,
            service_name=service_name,
            container_name=container_name,
            task_arn=task_arn,
            ec2_instance_id=ec2_instance_id,
            nlb_dns_name=nlb_dns_name,
            detection_mode=self.detection_mode.value,
            project_name=self.project_name,
            environment=self.environment
        )
        
        logger.info(f"Resource detection completed: {config}")
        return config
    
    def _detect_ecs_cluster(self) -> str:
        """ECSクラスターを検出"""
        logger.info("Detecting ECS cluster...")
        
        # 1. タグベース検索（優先）
        if self.detection_mode in [DetectionMode.AUTO, DetectionMode.TAGS]:
            clusters = self._search_ecs_clusters_by_tags()
            if clusters:
                logger.info(f"Found cluster by tags: {clusters[0]}")
                return clusters[0]
        
        # 2. 環境変数から取得（フォールバック）
        if cluster_name := os.getenv("CLUSTER_NAME"):
            logger.info(f"Found cluster from environment variable: {cluster_name}")
            return cluster_name
        
        # 3. 命名規則ベース検索（最後の手段）
        if self.detection_mode in [DetectionMode.AUTO, DetectionMode.NAMING]:
            cluster_name = self._search_ecs_clusters_by_naming()
            if cluster_name:
                logger.info(f"Found cluster by naming pattern: {cluster_name}")
                return cluster_name
        
        raise Exception(f"ECS cluster not found for project '{self.project_name}' in environment '{self.environment}'")
    
    def _detect_ecs_service(self, cluster_name: str) -> str:
        """ECSサービスを検出"""
        logger.info(f"Detecting ECS service in cluster: {cluster_name}")
        
        # 1. タグベース検索（優先）
        if self.detection_mode in [DetectionMode.AUTO, DetectionMode.TAGS]:
            services = self._search_ecs_services_by_tags(cluster_name)
            if services:
                logger.info(f"Found service by tags: {services[0]}")
                return services[0]
        
        # 2. 環境変数から取得（フォールバック）
        if service_name := os.getenv("SERVICE_NAME"):
            logger.info(f"Found service from environment variable: {service_name}")
            return service_name
        
        # 3. 命名規則ベース検索（フォールバック）
        if self.detection_mode in [DetectionMode.AUTO, DetectionMode.NAMING]:
            service_name = self._search_ecs_services_by_naming(cluster_name)
            if service_name:
                logger.info(f"Found service by naming pattern: {service_name}")
                return service_name
        
        # 4. 最後の手段：クラスター内の最初のサービスを取得
        try:
            result = subprocess.run([
                self.aws_cli_path, "ecs", "list-services",
                "--cluster", cluster_name,
                "--query", "serviceArns[0]",
                "--output", "text",
                "--region", self.aws_region
            ], capture_output=True, text=True, check=True)
            
            service_arn = result.stdout.strip()
            if service_arn and service_arn != "None":
                service_name = service_arn.split("/")[-1]
                logger.info(f"Found service as fallback: {service_name}")
                return service_name
        except subprocess.CalledProcessError as e:
            logger.warning(f"Failed to get first service as fallback: {e.stderr}")
        
        raise Exception(f"ECS service not found in cluster '{cluster_name}'")
    
    def _detect_task_arn(self, cluster_name: str, service_name: str) -> str:
        """実行中のタスクARNを検出"""
        logger.info(f"Detecting running task for service: {service_name}")
        
        try:
            result = subprocess.run([
                self.aws_cli_path, "ecs", "list-tasks",
                "--cluster", cluster_name,
                "--service-name", service_name,
                "--query", "taskArns[0]",
                "--output", "text",
                "--region", self.aws_region
            ], capture_output=True, text=True, check=True)
            
            task_arn = result.stdout.strip()
            if task_arn and task_arn != "None":
                logger.info(f"Found running task: {task_arn}")
                return task_arn
            else:
                raise Exception(f"No running tasks found for service {service_name}")
                
        except subprocess.CalledProcessError as e:
            raise Exception(f"Failed to list tasks: {e.stderr}")
    
    def _detect_container_name(self, cluster_name: str, task_arn: str) -> str:
        """コンテナ名を検出"""
        logger.info(f"Detecting container name for task: {task_arn}")
        
        # 1. 環境変数から取得
        if container_name := os.getenv("CONTAINER_NAME"):
            logger.info(f"Found container from environment variable: {container_name}")
            return container_name
        
        # 2. タスクから取得
        try:
            result = subprocess.run([
                self.aws_cli_path, "ecs", "describe-tasks",
                "--cluster", cluster_name,
                "--tasks", task_arn,
                "--query", "tasks[0].containers[0].name",
                "--output", "text",
                "--region", self.aws_region
            ], capture_output=True, text=True, check=True)
            
            container_name = result.stdout.strip()
            if container_name:
                logger.info(f"Found container: {container_name}")
                return container_name
            else:
                raise Exception("No container found in task")
                
        except subprocess.CalledProcessError as e:
            raise Exception(f"Failed to describe task: {e.stderr}")
    
    def _detect_ec2_instance(self) -> str:
        """EC2インスタンスを検出（Fargateの場合はオプショナル）"""
        logger.info("Detecting EC2 instance...")
        
        # 1. タグベース検索（優先）
        if self.detection_mode in [DetectionMode.AUTO, DetectionMode.TAGS]:
            instances = self._search_ec2_instances_by_tags()
            if instances:
                logger.info(f"Found EC2 instance by tags: {instances[0]}")
                return instances[0]
        
        # 2. 環境変数から取得（フォールバック）
        if instance_id := os.getenv("EC2_INSTANCE_ID"):
            logger.info(f"Found EC2 instance from environment variable: {instance_id}")
            return instance_id
        
        # 3. 命名規則ベース検索（フォールバック）
        if self.detection_mode in [DetectionMode.AUTO, DetectionMode.NAMING]:
            instance_id = self._search_ec2_instances_by_naming()
            if instance_id:
                logger.info(f"Found EC2 instance by naming pattern: {instance_id}")
                return instance_id
        
        # Fargateの場合はEC2インスタンスは不要
        logger.warning(f"EC2 instance not found for project '{self.project_name}' - this is normal for Fargate deployments")
        return "fargate-no-ec2"
    
    def _detect_nlb_dns(self) -> str:
        """NLB DNS名を検出（オプショナル）"""
        logger.info("Detecting NLB DNS name...")
        
        # 1. タグベース検索（優先）
        if self.detection_mode in [DetectionMode.AUTO, DetectionMode.TAGS]:
            dns_names = self._search_nlb_by_tags()
            if dns_names:
                logger.info(f"Found NLB DNS by tags: {dns_names[0]}")
                return dns_names[0]
        
        # 2. 環境変数から取得（フォールバック）
        if dns_name := os.getenv("NLB_DNS_NAME"):
            logger.info(f"Found NLB DNS from environment variable: {dns_name}")
            return dns_name
        
        # 3. 命名規則ベース検索（フォールバック）
        if self.detection_mode in [DetectionMode.AUTO, DetectionMode.NAMING]:
            dns_name = self._search_nlb_by_naming()
            if dns_name:
                logger.info(f"Found NLB DNS by naming pattern: {dns_name}")
                return dns_name
        
        # NLBはオプショナル
        logger.warning(f"NLB not found for project '{self.project_name}' - this is optional")
        return "no-nlb-configured"
    
    def _search_ecs_clusters_by_tags(self) -> List[str]:
        """タグベースでECSクラスターを検索（CDK対応）"""
        try:
            # まず、すべてのクラスターを取得
            result = subprocess.run([
                self.aws_cli_path, "ecs", "list-clusters",
                "--output", "json",
                "--region", self.aws_region
            ], capture_output=True, text=True, check=True)
            
            clusters_data = json.loads(result.stdout)
            clusters = clusters_data.get("clusterArns", [])
            matching_clusters = []
            
            for cluster_arn in clusters:
                cluster_name = cluster_arn.split("/")[-1]
                
                # タグベースの検索を試行
                try:
                    tag_result = subprocess.run([
                        self.aws_cli_path, "ecs", "describe-clusters",
                        "--clusters", cluster_name,
                        "--include", "TAGS",
                        "--query", "clusters[0].tags",
                        "--output", "json",
                        "--region", self.aws_region
                    ], capture_output=True, text=True, check=True)
                    
                    tags = json.loads(tag_result.stdout)
                    # Pythonでタグをフィルタリング
                    project_tag_found = False
                    if tags:  # tagsがNoneでない場合のみ処理
                        project_tag_found = any(
                            tag.get("key") == "Project" and tag.get("value") == self.project_name
                            for tag in tags
                        )
                    
                    if project_tag_found:
                        matching_clusters.append(cluster_name)
                        logger.info(f"Found cluster by tags: {cluster_name}")
                        continue
                        
                except subprocess.CalledProcessError:
                    pass
                
                # タグが見つからない場合は命名規則でフォールバック
                if self._matches_cluster_naming_pattern(cluster_name):
                    matching_clusters.append(cluster_name)
                    logger.info(f"Found cluster by naming pattern: {cluster_name}")
            
            return matching_clusters
            
        except subprocess.CalledProcessError as e:
            logger.warning(f"Failed to search clusters by tags: {e.stderr}")
            return []
    
    def _matches_cluster_naming_pattern(self, cluster_name: str) -> bool:
        """クラスター名が命名パターンにマッチするかチェック"""
        patterns = [
            f"{self.project_name}-cluster",
            f"minecraft-{self.environment}-cluster",
            f"minecraft-cluster",
            f"{self.project_name}-cdk-cluster",
            f"minecraft-cdk-cluster"
        ]
        
        for pattern in patterns:
            if pattern in cluster_name:
                return True
        return False
    
    def _search_ecs_clusters_by_naming(self) -> Optional[str]:
        """命名規則ベースでECSクラスターを検索（CDK対応）"""
        try:
            # CDKの命名規則に対応した複数のパターンを試行
            patterns = [
                f"{self.project_name}-cluster",
                f"minecraft-{self.environment}-cluster", 
                f"minecraft-cluster",
                f"{self.project_name}-cdk-cluster",  # CDKパターン
                f"minecraft-cdk-cluster",  # 実際のクラスター名
                f"*-cdk-cluster",  # CDKクラスターの汎用パターン
                f"*-cluster"  # 最後の手段としてクラスターを含むもの
            ]
            
            for pattern in patterns:
                if "*" in pattern:
                    # ワイルドカードパターンの場合、すべてのクラスターを取得してフィルタリング
                    result = subprocess.run([
                        self.aws_cli_path, "ecs", "list-clusters",
                        "--output", "json",
                        "--region", self.aws_region
                    ], capture_output=True, text=True, check=True)
                    
                    clusters = json.loads(result.stdout)
                    for cluster_arn in clusters:
                        cluster_name = cluster_arn.split("/")[-1]
                        if self._matches_pattern(cluster_name, pattern):
                            logger.info(f"Found cluster by wildcard pattern '{pattern}': {cluster_name}")
                            return cluster_name
                else:
                    # 通常のパターンマッチング
                    result = subprocess.run([
                        self.aws_cli_path, "ecs", "list-clusters",
                        "--query", f"clusterArns[?contains(@, '{pattern}')]",
                        "--output", "json",
                        "--region", self.aws_region
                    ], capture_output=True, text=True, check=True)
                    
                    clusters = json.loads(result.stdout)
                    if clusters:
                        cluster_name = clusters[0].split("/")[-1]
                        logger.info(f"Found cluster by pattern '{pattern}': {cluster_name}")
                        return cluster_name
            
            return None
            
        except subprocess.CalledProcessError as e:
            logger.warning(f"Failed to search clusters by naming: {e.stderr}")
            return None
    
    def _matches_pattern(self, name: str, pattern: str) -> bool:
        """名前がパターンにマッチするかチェック"""
        if "*" not in pattern:
            return pattern in name
        
        # シンプルなワイルドカードマッチング
        if pattern.startswith("*") and pattern.endswith("*"):
            return pattern[1:-1] in name
        elif pattern.startswith("*"):
            return name.endswith(pattern[1:])
        elif pattern.endswith("*"):
            return name.startswith(pattern[:-1])
        
        return False
    
    def _search_ecs_services_by_tags(self, cluster_name: str) -> List[str]:
        """タグベースでECSサービスを検索（CDK対応）"""
        try:
            # まず、すべてのサービスを取得
            result = subprocess.run([
                self.aws_cli_path, "ecs", "list-services",
                "--cluster", cluster_name,
                "--output", "json",
                "--region", self.aws_region
            ], capture_output=True, text=True, check=True)
            
            services_data = json.loads(result.stdout)
            services = services_data.get("serviceArns", [])
            matching_services = []
            
            for service_arn in services:
                service_name = service_arn.split("/")[-1]
                
                # タグベースの検索を試行
                try:
                    tag_result = subprocess.run([
                        self.aws_cli_path, "ecs", "describe-services",
                        "--cluster", cluster_name,
                        "--services", service_name,
                        "--query", "services[0].tags",
                        "--output", "json",
                        "--region", self.aws_region
                    ], capture_output=True, text=True, check=True)
                    
                    tags = json.loads(tag_result.stdout)
                    # Pythonでタグをフィルタリング
                    project_tag_found = False
                    if tags:  # tagsがNoneでない場合のみ処理
                        project_tag_found = any(
                            tag.get("key") == "Project" and tag.get("value") == self.project_name
                            for tag in tags
                        )
                    
                    if project_tag_found:
                        matching_services.append(service_name)
                        logger.info(f"Found service by tags: {service_name}")
                        continue
                        
                except subprocess.CalledProcessError:
                    pass
                
                # タグが見つからない場合は命名規則でフォールバック
                if self._matches_service_naming_pattern(service_name):
                    matching_services.append(service_name)
                    logger.info(f"Found service by naming pattern: {service_name}")
            
            return matching_services
            
        except subprocess.CalledProcessError as e:
            logger.warning(f"Failed to search services by tags: {e.stderr}")
            return []
    
    def _matches_service_naming_pattern(self, service_name: str) -> bool:
        """サービス名が命名パターンにマッチするかチェック"""
        patterns = [
            f"{self.project_name}-service",
            f"minecraft-{self.environment}-service",
            f"minecraft-service",
            "ECSMinecraftService",  # CDKの動的命名パターン
            "MinecraftService"  # より汎用的なパターン
        ]
        
        for pattern in patterns:
            if pattern in service_name:
                return True
        return False
    
    def _search_ecs_services_by_naming(self, cluster_name: str) -> Optional[str]:
        """命名規則ベースでECSサービスを検索（CDK対応）"""
        try:
            # CDKの動的命名に対応したパターン
            patterns = [
                f"{self.project_name}-service",
                f"minecraft-{self.environment}-service",
                f"minecraft-service",
                f"*ECSMinecraftService*",  # CDKの動的命名パターン
                f"*MinecraftService*",  # より汎用的なパターン
                f"*Service*"  # 最後の手段
            ]
            
            for pattern in patterns:
                if "*" in pattern:
                    # ワイルドカードパターンの場合
                    result = subprocess.run([
                        self.aws_cli_path, "ecs", "list-services",
                        "--cluster", cluster_name,
                        "--output", "json",
                        "--region", self.aws_region
                    ], capture_output=True, text=True, check=True)
                    
                    services = json.loads(result.stdout)
                    for service_arn in services:
                        service_name = service_arn.split("/")[-1]
                        if self._matches_pattern(service_name, pattern):
                            logger.info(f"Found service by wildcard pattern '{pattern}': {service_name}")
                            return service_name
                else:
                    # 通常のパターンマッチング
                    result = subprocess.run([
                        self.aws_cli_path, "ecs", "list-services",
                        "--cluster", cluster_name,
                        "--query", f"serviceArns[?contains(@, '{pattern}')]",
                        "--output", "json",
                        "--region", self.aws_region
                    ], capture_output=True, text=True, check=True)
                    
                    services = json.loads(result.stdout)
                    if services:
                        service_name = services[0].split("/")[-1]
                        logger.info(f"Found service by pattern '{pattern}': {service_name}")
                        return service_name
            
            return None
            
        except subprocess.CalledProcessError as e:
            logger.warning(f"Failed to search services by naming: {e.stderr}")
            return None
    
    def _search_ec2_instances_by_tags(self) -> List[str]:
        """タグベースでEC2インスタンスを検索"""
        try:
            result = subprocess.run([
                self.aws_cli_path, "ec2", "describe-instances",
                "--filters", "Name=instance-state-name,Values=running",
                "--query", f"Reservations[].Instances[?Tags[?Key=='Project' && Value=='{self.project_name}'] && Tags[?Key=='Environment' && Value=='{self.environment}']].InstanceId",
                "--output", "json",
                "--region", self.aws_region
            ], capture_output=True, text=True, check=True)
            
            instances = json.loads(result.stdout)
            return [instance for sublist in instances for instance in sublist]
            
        except subprocess.CalledProcessError as e:
            logger.warning(f"Failed to search EC2 instances by tags: {e.stderr}")
            return []
    
    def _search_ec2_instances_by_naming(self) -> Optional[str]:
        """命名規則ベースでEC2インスタンスを検索"""
        try:
            patterns = [
                f"{self.project_name}-proxy",
                f"minecraft-{self.environment}-proxy",
                f"minecraft-proxy"
            ]
            
            for pattern in patterns:
                result = subprocess.run([
                    self.aws_cli_path, "ec2", "describe-instances",
                    "--filters", "Name=instance-state-name,Values=running",
                    "--query", f"Reservations[].Instances[?Tags[?Key=='Name' && contains(Value, '{pattern}')]].InstanceId",
                    "--output", "json",
                    "--region", self.aws_region
                ], capture_output=True, text=True, check=True)
                
                instances = json.loads(result.stdout)
                if instances and instances[0]:
                    return instances[0][0]
            
            return None
            
        except subprocess.CalledProcessError as e:
            logger.warning(f"Failed to search EC2 instances by naming: {e.stderr}")
            return None
    
    def _search_nlb_by_tags(self) -> List[str]:
        """タグベースでNLBを検索"""
        try:
            result = subprocess.run([
                self.aws_cli_path, "elbv2", "describe-load-balancers",
                "--query", f"LoadBalancers[?Tags[?Key=='Project' && Value=='{self.project_name}'] && Tags[?Key=='Environment' && Value=='{self.environment}']].DNSName",
                "--output", "json",
                "--region", self.aws_region
            ], capture_output=True, text=True, check=True)
            
            dns_names = json.loads(result.stdout)
            return [dns for sublist in dns_names for dns in sublist]
            
        except subprocess.CalledProcessError as e:
            logger.warning(f"Failed to search NLB by tags: {e.stderr}")
            return []
    
    def _search_nlb_by_naming(self) -> Optional[str]:
        """命名規則ベースでNLBを検索"""
        try:
            patterns = [
                f"{self.project_name}-nlb",
                f"minecraft-{self.environment}-nlb",
                f"minecraft-nlb"
            ]
            
            for pattern in patterns:
                result = subprocess.run([
                    self.aws_cli_path, "elbv2", "describe-load-balancers",
                    "--query", f"LoadBalancers[?contains(LoadBalancerName, '{pattern}')].DNSName",
                    "--output", "json",
                    "--region", self.aws_region
                ], capture_output=True, text=True, check=True)
                
                dns_names = json.loads(result.stdout)
                if dns_names:
                    return dns_names[0]
            
            return None
            
        except subprocess.CalledProcessError as e:
            logger.warning(f"Failed to search NLB by naming: {e.stderr}")
            return None

def create_resource_detector() -> ResourceDetector:
    """環境変数からResourceDetectorを作成"""
    environment = os.getenv("ENVIRONMENT", "dev")
    project_name = os.getenv("PROJECT_NAME", "t-tkm-minecraft-mcp2")  # 実際のタグ値に合わせる
    aws_region = os.getenv("AWS_REGION", "ap-northeast-1")
    
    return ResourceDetector(environment, project_name, aws_region)

if __name__ == "__main__":
    # テスト用
    detector = create_resource_detector()
    config = detector.detect_all_resources()
    print(json.dumps(config.__dict__, indent=2))
