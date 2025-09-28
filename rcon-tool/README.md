# RCON Tool - FastMCP Server
Minecraft RCON MCP Server for AWS ECS（FastMCP実装）

## 概要

AWS ECS上で実行されているMinecraftサーバーをRCON経由で操作するためのFastMCPサーバーです。Claude DesktopからMinecraftサーバーを管理するために使用されます。

## 機能

- **RCONコマンド実行**: MinecraftサーバーにRCONコマンドを送信
- **プレイヤー管理**: オンラインプレイヤーの一覧表示
- **サーバー統計**: ECSタスクの状態とサーバー統計情報の取得
- **ログ表示**: サーバーログの取得と表示
- **ヘルプ機能**: Minecraftコマンドのヘルプ表示

## 前提条件

- **Python 3.12.8**
- AWS CLI設定済み（AWS SSOベース）
- AWS ECSクラスターでMinecraftサーバーが実行中
- `ecs-exec.sh`スクリプトが利用可能

詳細なセットアップ手順は[メインREADME](../README.md)を参照してください。

## インストール

### FastMCP公式推奨セットアップ

```bash
# プロジェクトディレクトリに移動
cd rcon-tool

# 仮想環境の作成とアクティベート
python -m venv .venv
source .venv/bin/activate  # Windows: .venv\Scripts\activate

# FastMCPと依存関係のインストール
pip install -e .
```

### 環境変数の設定

```bash
# .envファイルの作成（プロジェクトルートに）
cp ../env.example .env

# 必要な環境変数を設定
# CLUSTER_NAME=your-cluster-name
# SERVICE_NAME=your-service-name
# CONTAINER_NAME=minecraft
# AWS_REGION=ap-northeast-1
# AWS_PROFILE=your-profile
```

## 使用方法

### MCPサーバーとして実行

```bash
# サーバーの起動
python rcon.py
```

### 利用可能なツール

1. **rcon(command: str)**: カスタムRCONコマンドを実行
   - 例: `rcon("weather clear")`, `rcon("say Hello, players!")`

## 設定

### 環境変数

以下の環境変数で設定が可能です：

- `CLUSTER_NAME`: ECSクラスター名
- `SERVICE_NAME`: ECSサービス名
- `CONTAINER_NAME`: コンテナ名（デフォルト: minecraft）
- `TASK_ARN`: タスクARN
- `AWS_REGION`: AWSリージョン
- `AWS_PROFILE`: AWSプロファイル
- `ENVIRONMENT`: 環境名
- `PROJECT_NAME`: プロジェクト名

### Claude Desktopでの設定

```json
{
  "mcpServers": {
    "minecraft-rcon": {
      "command": "python",
      "args": ["/path/to/rcon-tool/rcon.py"],
      "env": {
        "AWS_PROFILE": "your-profile",
        "AWS_REGION": "ap-northeast-1"
      }
    }
  }
}
```

## 利用可能なコマンド例

### 基本的なRCONコマンド

```bash
# プレイヤー一覧
rcon("list")

# 天気変更
rcon("weather clear")
rcon("weather rain")

# 時間設定
rcon("time set day")
rcon("time set night")

# メッセージ送信
rcon("say Hello, players!")

# ゲームモード変更
rcon("gamemode creative @a")
rcon("gamemode survival @a")
```

### 建築・ブロック操作

```bash
# プレイヤー座標取得
rcon("data get entity @p Pos")

# ブロック設置
rcon("setblock 100 64 100 stone")

# 範囲塗りつぶし
rcon("fill 100 64 100 110 74 110 stone")

# 構造物複製
rcon("clone 100 64 100 110 74 110 200 64 200")
```

### エンティティ管理

```bash
# エンティティ召喚
rcon("summon cow 100 64 100")

# テレポート
rcon("tp @p 100 64 100")

# エンティティ削除
rcon("kill @e[type=cow,distance=..10]")
```

## 開発

### 開発環境のセットアップ

```bash
# 仮想環境をアクティベート
source .venv/bin/activate  # Windows: .venv\Scripts\activate

# 開発用依存関係のインストール
pip install -e .

# コードの実行
python rcon.py
```

### プロジェクト構造

```
rcon-tool/
├── rcon.py              # FastMCPサーバー実装
├── resource_detector.py # AWSリソース検出
├── pyproject.toml       # プロジェクト設定
├── requirements.txt     # 依存関係
└── README.md           # このファイル
```

### FastMCPの特徴

- **クラスベース実装**: 保守性と拡張性を向上
- **最小限の依存関係**: `fastmcp`と`python-dotenv`のみ
- **標準的なプロジェクト構造**: FastMCPの推奨パターンに準拠
- **適切なエラーハンドリング**: 堅牢なエラー処理

## トラブルシューティング

### よくある問題

1. **AWS認証エラー**
   ```bash
   aws sso login
   aws sts get-caller-identity
   ```

2. **環境変数が設定されていない**
   ```bash
   # .envファイルの確認
   cat .env
   
   # 環境変数の確認
   python -c "import os; print('AWS_PROFILE:', os.getenv('AWS_PROFILE'))"
   ```

3. **ECSリソースが見つからない**
   ```bash
   # リソース検出の確認
   python -c "from resource_detector import create_resource_detector; print(create_resource_detector().detect_all_resources())"
   ```

## ライセンス

MIT License