#!/usr/bin/env python3
"""
Minecraft RCON MCP Server
統合版 - 安定性と機能性を兼ね備えたバージョン
"""
import asyncio
import concurrent.futures
import os
import subprocess
import sys
from typing import Any, Dict, List, Optional

from fastmcp import FastMCP
from resource_detector import ResourceConfig, create_resource_detector


class MinecraftRCONServer:
    """Minecraft RCON MCP Server"""
    
    def __init__(self):
        self.mcp = FastMCP("minecraft-rcon-ecs")
        self.resources = None
        self.project_root = None
        self._setup()
        self._register_tools()
    
    def _setup(self):
        """サーバーの初期設定"""
        self.log("Minecraft RCON MCP Server starting...")
        
        # プロジェクトルートを取得
        self.project_root = self._get_project_root()
        self.log(f"Detected PROJECT_ROOT: {self.project_root}")
        
        # .envファイルを読み込み
        self._load_env_file()
        
        # 環境変数のログ出力
        self.log(f"Environment variables:")
        self.log(f"  PROJECT_ROOT: {self.project_root}")
        self.log(f"  AWS_REGION: {os.getenv('AWS_REGION', 'not set')}")
        self.log(f"  ENVIRONMENT: {os.getenv('ENVIRONMENT', 'not set')}")
        self.log(f"  PROJECT_NAME: {os.getenv('PROJECT_NAME', 'not set')}")
        
        # リソース検出の初期化
        self._initialize_resources()
        
        self.log("MCP Server initialized")
    
    def _get_project_root(self):
        """プロジェクトルートを動的に取得する"""
        current_dir = os.path.dirname(os.path.abspath(__file__))
        
        # プロジェクトルート（.envファイルがあるディレクトリ）を探す
        search_dir = current_dir
        while search_dir != os.path.dirname(search_dir):
            env_file = os.path.join(search_dir, ".env")
            if os.path.exists(env_file):
                return search_dir
            search_dir = os.path.dirname(search_dir)
        
        # .envファイルが見つからない場合は、現在のディレクトリの親を使用
        return os.path.dirname(current_dir)
    
    def _load_env_file(self, env_file_path: str = None):
        """プロジェクトの.envファイルを読み込む"""
        if env_file_path is None:
            env_file_path = os.path.join(self.project_root, ".env")
        
        self.log(f"Loading .env file from: {env_file_path}")
        
        if not os.path.exists(env_file_path):
            self.log(f"Warning: .env file not found at {env_file_path}")
            return
        
        try:
            with open(env_file_path, 'r', encoding='utf-8') as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith('#'):
                        continue
                    
                    if '=' in line:
                        key, value = line.split('=', 1)
                        key = key.strip()
                        value = value.strip()
                        
                        old_value = os.environ.get(key, "not set")
                        os.environ[key] = value
                        self.log(f"Set {key}={value} (was: {old_value})")
                        
        except Exception as e:
            self.log(f"Warning: Failed to load .env file: {e}")
    
    def _initialize_resources(self):
        """リソース検出の初期化"""
        try:
            detector = create_resource_detector()
            self.resources = detector.detect_all_resources()
            self.log(f"Resource detection successful:")
            self.log(f"  Cluster: {self.resources.cluster_name}")
            self.log(f"  Service: {self.resources.service_name}")
            self.log(f"  Container: {self.resources.container_name}")
            self.log(f"  Detection mode: {self.resources.detection_mode}")
        except Exception as e:
            self.log(f"WARNING: Failed to detect resources: {e}")
            self.log("Creating fallback resource configuration...")
            
            # フォールバック設定を作成
            from resource_detector import ResourceConfig
            
            self.resources = ResourceConfig(
                cluster_name=os.getenv("CLUSTER_NAME"),
                service_name=os.getenv("SERVICE_NAME"),
                container_name=os.getenv("CONTAINER_NAME"),
                task_arn=os.getenv("TASK_ARN"),
                ec2_instance_id="",
                nlb_dns_name="",
                detection_mode="",
                project_name="",
                environment=""
            )
            
            self.log(f"Using fallback configuration:")
            self.log(f"  Cluster: {self.resources.cluster_name}")
            self.log(f"  Service: {self.resources.service_name}")
            self.log(f"  Container: {self.resources.container_name}")
    
    def _register_tools(self):
        """MCPツールを登録"""
        @self.mcp.tool()
        def rcon(command: str) -> str:
            """Perform RCON operations on the Minecraft server. Core principles and command reference:

CORE SAFETY PRINCIPLES:
1. Always get player coordinates before building operations
   Use: data get entity <player_name> Pos
   Returns: [X.XXd, Y.XXd, Z.XXd]
   Store and reuse as base for safe building operations
   日本語補足: プレイヤー座標を事前取得することで安全で予測可能な建築が可能になります

2. Prefer absolute coordinates for structures  
   Avoid building large structures relative to ~ (current position)
   Confirm positions before execution to prevent accidents
   日本語補足: 相対座標~は便利ですが誤って位置がずれることがあります。安全な構造物再現には絶対座標を推奨します

3. Validate before executing dangerous operations
   Check block existence (especially modded blocks)
   Be cautious with fill/clone commands (large ranges can overwrite builds)
   Always ask for confirmation on operations affecting >100 blocks
   日本語補足: Mod追加ブロックは存在確認が必要です。fillやcloneは範囲指定を誤ると既存建築を破壊する危険があります

POSITION AND BUILDING COMMANDS:
- Get player position: data get entity <player_name> Pos
- Place single block: setblock <x> <y> <z> <block_type>[properties]
- Fill area: fill <x1> <y1> <z1> <x2> <y2> <z2> <block_type> [replace|keep|outline|hollow]
- Clone structures: clone <x1> <y1> <z1> <x2> <y2> <z2> <dest_x> <dest_y> <dest_z> [replace|masked]
日本語補足: setblockは単体ブロック、fillは範囲、cloneは複製です。座標の範囲指定は始点と終点の両方を含むため意図した大きさを意識してください

ENTITY MANAGEMENT:
- Summon entity: summon <entity_type> <x> <y> <z> [nbt]
- Teleport entities: tp @e[type=<entity_type>] <x> <y> <z>
- Execute as entity: execute as @e[type=<entity_type>] at @s run <command>
- Kill specific entities: kill @e[type=<entity_type>,distance=..10]
日本語補足: summonは新規生成、tpは移動、executeは特定エンティティとしてコマンド実行します。モブ制御やイベント演出に有効です

PLAYER TELEPORTATION AND VIEW:
- Teleport player: tp @p <x> <y> <z>
- Spectate entity: spectate <target> [player]
- Execute from position: execute positioned <x> <y> <z> run <command>
- Set spawn point: spawnpoint <player> <x> <y> <z>
日本語補足: 観戦モードやテレポートで視点操作が可能です。execute positionedは特定座標からのコマンド実行に便利です

ITEMS AND EFFECTS:
Give Items (Modern 1.20.5+ syntax):
- give <player> <item> [count]
- give <player> iron_sword[enchantments={levels:{"minecraft:sharpness":5}}] 1
- give @a iron_pickaxe[unbreakable={}]
- give <player> potion[potion_contents={potion:"minecraft:fire_resistance"}]

Status Effects:
- effect give @a speed 300 2
- effect give <player> night_vision 1000 1  
- effect give <player> water_breathing infinite 1 true
- effect clear <player> [effect]
日本語補足: giveはアイテム配布、effectはステータス効果付与です。クリエイティブでのテストやイベント演出に使えます

WORLD MANAGEMENT:
- Weather: weather clear|rain|thunder [duration]
- Time: time set day|night|noon|midnight or time set <value>
- Game rules: gamerule <rule> <value> (keepInventory, mobGriefing, etc.)
- World border: worldborder set <size>, worldborder center <x> <z>
日本語補足: 天候・時間・ゲームルール・ワールドボーダーの制御が可能です

TARGETING SELECTORS:
- @a: all players
- @p: nearest player  
- @r: random player
- @e[type=<entity>]: all entities of specific type
- @e[type=<entity>,limit=1]: single entity of type
- <player_name>: specific player by name

Selector Arguments:
- distance=..10: within 10 blocks
- x=100,y=64,z=100,distance=..5: near specific coordinates  
- level=10..20: experience levels 10-20
- gamemode=creative: creative mode players only
日本語補足: ターゲット指定子は柔軟に使えます。@aで全員、プレイヤー名で個別指定可能です

BLOCK STATES AND PROPERTIES:
- Syntax: block_type[property=value]
- Example: lantern[hanging=true]
- Multiple properties: block_type[prop1=value1,prop2=value2]
- Common properties: facing, waterlogged, lit, open, powered
日本語補足: ブロックの状態（点灯・向きなど）はプロパティで指定します。
細かい制御が可能です

COORDINATE SYSTEMS:
- Absolute: <x> <y> <z> (exact world position)
- Relative: ~ (current position), ~1 (+1 offset), ~-1 (-1 offset)
- Local: ^left ^up ^forward (relative to entity facing)
- Coordinate ranges are INCLUSIVE: ~0 to ~15 = 16 blocks total
日本語補足: ~は便利ですが誤差で大規模建築にズレが出やすいです。
基本は絶対座標を使うのが安全です

HIGH RISK OPERATIONS - USE WITH EXTREME CAUTION:
- fill with large ranges (>1000 blocks)
- clone operations affecting existing builds
- kill @e (kills ALL entities including items)
- /stop or /restart commands
日本語補足: 大規模なfill・clone操作や全エンティティ削除は
既存建築を破壊する危険があります

SAFETY CHECKLIST BEFORE MAJOR OPERATIONS:
1. Get player position and survey area
2. Calculate exact block count affected
3. Verify all block types exist (especially modded blocks)
4. Confirm operation with user if affecting >100 blocks
5. Provide undo method or backup strategy
日本語補足: 大規模操作前は必ず範囲確認・ブロック存在確認・
バックアップ戦略を用意してください

COMMON GOTCHAS TO AVOID:
- Never use large relative fills (~) for structures
- Remember both corners are inclusive in fill/clone ranges
- Some commands need player context (e.g., locate)
- Test modded blocks before using in large operations
- Coordinates Y<-64 or Y>320 may be invalid in some versions
日本語補足: よくある失敗は「相対座標で建築してズレる」
「範囲指定を誤って破壊」「存在しないブロック指定」です

EMERGENCY FIXES:
- Undo fill: fill <x1> <y1> <z1> <x2> <y2> <z2> air
- Restore player: tp <player> 0 100 0
- Clear effects: effect clear @a
- Reset weather: weather clear
日本語補足: 緊急時は該当範囲をairで埋める、
プレイヤーを安全な場所にテレポートなどで対処します

VERSION COMPATIBILITY NOTES:
- 1.20.5+: New item component syntax with brackets
- 1.19+: Deep dark blocks (sculk family)
- 1.17+: Caves & cliffs blocks, extended height limits
- 1.16+: Nether update blocks
- 1.13+: Block ID flattening (minecraft:stone vs stone)
日本語補足: バージョンによりブロックIDや構文が異なります。特に1.13以降のフラット化と1.20.5以降のアイテム構文変更に注意してください

Always prioritize safety over convenience. When in doubt, use smaller operations and absolute coordinates.
Always explain what each command does and potential risks to the user.
            """
            try:
                return self._execute_rcon_command(command)
            except Exception as e:
                return f"Error: {str(e)}"
    
    def _execute_rcon_command(self, command: str) -> str:
        """Execute RCON command on Minecraft server via ECS EXEC."""
        self.log(f"execute_rcon_command() called with command: {command}")
        try:
            ecs_exec_script = f"{self.project_root}/scripts/ecs-exec.sh"
            env = os.environ.copy()
            
            # 環境変数を明示的に設定
            env.update({
                "CLUSTER_NAME": self.resources.cluster_name,
                "SERVICE_NAME": self.resources.service_name,
                "CONTAINER_NAME": self.resources.container_name,
                "TASK_ARN": self.resources.task_arn,
                "AWS_REGION": os.getenv("AWS_REGION"),
                "AWS_PROFILE": os.getenv("AWS_PROFILE"),
                "ENVIRONMENT": os.getenv("ENVIRONMENT"),
                "PROJECT_NAME": os.getenv("PROJECT_NAME")
            })
            
            # デバッグ用：環境変数をログ出力
            self.log(f"DEBUG: Passing environment variables to ecs-exec.sh:")
            self.log(f"  CLUSTER_NAME: {env.get('CLUSTER_NAME')}")
            self.log(f"  SERVICE_NAME: {env.get('SERVICE_NAME')}")
            self.log(f"  CONTAINER_NAME: {env.get('CONTAINER_NAME')}")
            self.log(f"  TASK_ARN: {env.get('TASK_ARN')}")
            self.log(f"  AWS_PROFILE: {env.get('AWS_PROFILE')}")
            
            self.log(f"Running: {ecs_exec_script} rcon \"{command}\"")
            result = subprocess.run([
                ecs_exec_script, "rcon", command
            ], capture_output=True, text=True, check=True, env=env, cwd=self.project_root)
            
            # 出力から不要なデバッグ情報をフィルタリング
            output_lines = result.stdout.split('\n')
            filtered_output = []
            for line in output_lines:
                if not any(prefix in line for prefix in [
                    '[INFO]', '[SUCCESS]', '[WARNING]', '[ERROR]', 'DEBUG:',
                    'Executing RCON command:'
                ]):
                    if line.strip():
                        filtered_output.append(line)
            
            final_output = '\n'.join(filtered_output).strip()
            self.log(f"RCON command result: {final_output}")
            return (
                final_output if final_output
                else "Command executed successfully (no output)"
            )
            
        except subprocess.CalledProcessError as e:
            self.log(f"RCON command error: {e.stderr if e.stderr else str(e)}")
            # エラー出力からも不要な情報をフィルタリング
            error_output = e.stderr if e.stderr else str(e)
            error_lines = error_output.split('\n')
            filtered_errors = []
            for line in error_lines:
                if not any(prefix in line for prefix in [
                    '[INFO]', '[SUCCESS]', '[WARNING]', 'DEBUG:'
                ]):
                    if line.strip():
                        filtered_errors.append(line)
            filtered_error = '\n'.join(filtered_errors).strip()
            return (
                f"Error executing RCON command: "
                f"{filtered_error if filtered_error else str(e)}"
            )
        except Exception as e:
            self.log(f"RCON command unexpected error: {str(e)}")
            return f"Unexpected error: {str(e)}"
    
    def log(self, message: str):
        """シンプルなログ出力（stderrに出力してBrokenPipeErrorを回避）"""
        try:
            print(f"[MCP] {message}", file=sys.stderr)
        except BrokenPipeError:
            # クライアントが切断した場合はログ出力をスキップ
            pass
    
    def run(self):
        """MCPサーバーを実行"""
        self.log("Starting Minecraft RCON MCP server...")
        try:
            self.mcp.run()
            self.log("Minecraft RCON MCP server finished running")
        except BrokenPipeError:
            # Claude Desktopが切断した場合の正常な終了
            self.log("Client disconnected (normal shutdown)")
        except Exception as e:
            self.log(f"Error running MCP server: {e}")
            import traceback
            traceback.print_exc(file=sys.stderr)
            sys.exit(1)


def main():
    """メイン関数"""
    server = MinecraftRCONServer()
    server.run()


if __name__ == "__main__":
    main()