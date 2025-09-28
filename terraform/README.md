# Minecraft on AWS ECS - Terraform

Terraformを使用してMinecraftサーバーをAWS ECS上で運用するためのインフラストラクチャコードです。

> **注意**: このTerraform設定は付録です。メインはCDKベースです。

## 前提条件

- **Terraform 1.6.0**
- AWS CLI設定済み（AWS SSOベース）
- 適切なAWS権限

詳細なセットアップ手順は[メインREADME](../README.md)を参照してください。

## セットアップ

```bash
cd terraform

# 環境変数の設定は[メインREADME](../README.md#3-2-環境変数の設定)で実施済みであることを確認してください
```

## デプロイ

```bash
# Terraformの初期化
terraform init

# デプロイ前の確認
terraform plan

# デプロイ実行
terraform apply

# リソースの削除
terraform destroy
```

## モジュール構成

- **networking**: VPC、サブネット、セキュリティグループ
- **storage**: EFSファイルシステム
- **ec2**: ポートフォワーディング用EC2
- **load-balancer**: ネットワークロードバランサー
- **ecs**: ECSクラスター、タスク定義、サービス
- **monitoring**: CloudWatchダッシュボード
- **backup**: バックアップ設定

## プロジェクト構造

```
terraform/
├── main.tf                          # メインのTerraform設定
├── provider.tf                      # プロバイダー設定
├── variables.tf                     # 変数定義
├── README.md                        # このファイル
└── modules/                         # モジュールディレクトリ
    ├── networking/                  # ネットワークモジュール
    ├── storage/                     # ストレージモジュール
    ├── ec2/                         # EC2モジュール
    ├── load-balancer/               # ロードバランサーモジュール
    ├── ecs/                         # ECSモジュール
    ├── monitoring/                  # モニタリングモジュール
    └── backup/                      # バックアップモジュール
```

## 接続

```bash
# ロードバランサー経由（推奨）
terraform output load_balancer_dns_name

# EC2プロキシ経由
terraform output ec2_proxy_public_ip
ssh -L 25565:localhost:25565 ec2-user@<proxy-ip>
```

## ライセンス

このプロジェクトはMITライセンスの下で公開されています。