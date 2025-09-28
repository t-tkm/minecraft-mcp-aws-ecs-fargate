#!/usr/bin/env python3
import os
import aws_cdk as cdk
from dotenv import load_dotenv
from minecraft_stack import MinecraftStack

# .envファイルを読み込み
load_dotenv()

app = cdk.App()

# プロジェクト名から自動生成
project_name = os.getenv('PROJECT_NAME', 'minecraft-mcp')
stack_name = f"{project_name}-cdk-stack"

MinecraftStack(app, stack_name,
    env=cdk.Environment(
        # accountとregion未指定で自動検出
    ),
    description="Minecraft server on AWS ECS with CDK"
)

app.synth()
