# Minecraft on AWS ECS - AWS CDK

AWS CDK Pythonを使用してMinecraftサーバーをAWS ECS上で運用するためのインフラストラクチャコードです。

## 前提条件

- **Python 3.12.8**
- **Node.js 23.11.0**（CDK用）
- AWS CLI設定済み（AWS SSOベース）
- 適切なAWS権限

詳細なセットアップ手順は[メインREADME](../README.md)を参照してください。

## セットアップ

```bash
cd cdk

# Python仮想環境の作成とアクティベート
python -m venv .venv
source .venv/bin/activate  # Windows: .venv\Scripts\activate

# 依存関係のインストール
pip install -r requirements.txt

# CDKブートストラップ（初回のみ）
npx cdk bootstrap
```

## デプロイ

```bash
# デプロイ前の確認
npx cdk synth
npx cdk diff

# デプロイ実行
npx cdk deploy

# リソースの削除
npx cdk destroy
```

## スタック構成

- **NetworkingStack**: VPC、サブネット、セキュリティグループ
- **StorageStack**: EFSファイルシステム
- **EC2ProxyStack**: ポートフォワーディング用EC2
- **LoadBalancerStack**: ネットワークロードバランサー
- **ECSStack**: ECSクラスター、タスク定義、サービス
- **MonitoringStack**: CloudWatchダッシュボード

## プロジェクト構造

```
cdk/
├── app.py                          # CDKアプリケーションのエントリーポイント
├── cdk.json                        # CDK設定ファイル
├── requirements.txt                 # Python依存関係
├── README.md                       # このファイル
└── minecraft_stack/                # スタックモジュール
    ├── minecraft_stack.py          # メインスタック
    ├── networking.py               # ネットワークリソース
    ├── storage.py                  # ストレージリソース
    ├── ec2_proxy.py                # EC2プロキシリソース
    ├── load_balancer.py            # ロードバランサーリソース
    ├── ecs.py                      # ECSリソース
    └── monitoring.py               # モニタリングリソース
```

## ライセンス

このプロジェクトはMITライセンスの下で公開されています。