#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

# =============================================================================
# Minecraft ECS Exec Script
# =============================================================================
# AWS ECS EXEC経由でMinecraftサーバーを直接操作するスクリプト

# スクリプトの基本設定
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ログレベル設定
# 0: ERROR only, 1: WARNING+, 2: INFO+, 3: DEBUG+
LOG_LEVEL="${LOG_LEVEL:-0}"

# 環境変数を保護（MCPサーバーから渡された環境変数を優先）
TEMP_CLUSTER_NAME="${CLUSTER_NAME:-}"
TEMP_SERVICE_NAME="${SERVICE_NAME:-}"
TEMP_CONTAINER_NAME="${CONTAINER_NAME:-}"
TEMP_TASK_ARN="${TASK_ARN:-}"

# MCPサーバーから渡された環境変数が存在する場合は復元
if [ -n "$TEMP_CLUSTER_NAME" ]; then
    CLUSTER_NAME="$TEMP_CLUSTER_NAME"
fi
if [ -n "$TEMP_SERVICE_NAME" ]; then
    SERVICE_NAME="$TEMP_SERVICE_NAME"
fi
if [ -n "$TEMP_CONTAINER_NAME" ]; then
    CONTAINER_NAME="$TEMP_CONTAINER_NAME"
fi
if [ -n "$TEMP_TASK_ARN" ]; then
    TASK_ARN="$TEMP_TASK_ARN"
fi

# ログディレクトリ設定
LOGS_DIR="${LOGS_DIR:-$PROJECT_ROOT/logs}"

# 色付き出力の定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ログレベル制御付き色付き出力関数
print_debug() {
    if [ "$LOG_LEVEL" -ge 3 ]; then
        echo -e "${CYAN}[DEBUG]${NC} $1" >&2
    fi
}

print_status() {
    if [ "$LOG_LEVEL" -ge 2 ]; then
        echo -e "${BLUE}[INFO]${NC} $1" >&2
    fi
}

print_success() {
    if [ "$LOG_LEVEL" -ge 1 ]; then
        echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
    fi
}

print_warning() {
    if [ "$LOG_LEVEL" -ge 1 ]; then
        echo -e "${YELLOW}[WARNING]${NC} $1" >&2
    fi
}

print_error() {
    if [ "$LOG_LEVEL" -ge 0 ]; then
        echo -e "${RED}[ERROR]${NC} $1" >&2
    fi
}

# 常に表示されるメッセージ（ログレベルに関係なく）
print_always() {
    echo -e "${BLUE}[STATUS]${NC} $1" >&2
}

# 進行中表示（ドットアニメーション付き）
print_progress() {
    local message="$1"
    local duration="${2:-3}"
    
    echo -n -e "${BLUE}[STATUS]${NC} $message" >&2
    
    for i in $(seq 1 $duration); do
        echo -n "." >&2
        sleep 0.5
    done
    
    echo "" >&2
}

print_header() {
    echo -e "${CYAN}${BOLD}================================${NC}"
    echo -e "${CYAN}${BOLD} $1${NC}"
    echo -e "${CYAN}${BOLD}================================${NC}"
}

# AWS設定
AWS_REGION="${AWS_REGION:-ap-northeast-1}"

# デバッグ用：環境変数の状態を確認
print_debug "DEBUG: Checking environment variables:"
print_debug "  CLUSTER_NAME: '${CLUSTER_NAME:-not set}'"
print_debug "  SERVICE_NAME: '${SERVICE_NAME:-not set}'"
print_debug "  CONTAINER_NAME: '${CONTAINER_NAME:-not set}'"
print_debug "  TASK_ARN: '${TASK_ARN:-not set}'"
print_debug "  AWS_PROFILE: '${AWS_PROFILE:-not set}'"

# リソース検出関数（必要時のみ実行）
detect_resources() {
    print_always "Starting ECS Exec Script..."
    if [ -z "${CLUSTER_NAME:-}" ] || [ -z "${SERVICE_NAME:-}" ] || [ -z "${CONTAINER_NAME:-}" ]; then
        print_always "Detecting ECS resources"
        print_progress "Running resource detection" 3
        set +e
        detection_output=$(./scripts/resource_detector.sh ecs 2>&1)
        detection_exit_code=$?
        set -e
        
        if [ $detection_exit_code -eq 0 ]; then
            # 環境変数設定行のみを抽出
            env_lines=$(echo "$detection_output" | grep "^export ")
            eval "$env_lines"
            print_always "ECS resource detection completed"
        else
            print_error "ECS resource detection failed: $detection_output"
            exit 1
        fi
    else
        print_always "Using provided ECS environment variables"
    fi
}

# 検出されたリソースを確認（ECS操作用のみ）
CLUSTER_NAME="${CLUSTER_NAME:-}"
SERVICE_NAME="${SERVICE_NAME:-}"
CONTAINER_NAME="${CONTAINER_NAME:-minecraft}"

# デバッグ用：最終的な環境変数の状態を確認
print_debug "DEBUG: Final environment variables:"
print_debug "  CLUSTER_NAME: '${CLUSTER_NAME:-not set}'"
print_debug "  SERVICE_NAME: '${SERVICE_NAME:-not set}'"
print_debug "  CONTAINER_NAME: '${CONTAINER_NAME:-not set}'"
print_debug "  TASK_ARN: '${TASK_ARN:-not set}'"
print_debug "  AWS_PROFILE: '${AWS_PROFILE:-not set}'"

# 依存関係チェック
check_dependencies() {
    print_progress "Checking dependencies" 2
    local missing_deps=()
    
    if ! command -v aws &> /dev/null; then
        missing_deps+=("aws")
    fi
    
    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        print_error "Missing dependencies: ${missing_deps[*]}"
        exit 1
    fi
    print_always "Dependencies verified"
}

# AWS認証チェック
check_aws_auth() {
    print_progress "Checking AWS authentication" 3
    if [ -n "$AWS_PROFILE" ]; then
        if ! aws sts get-caller-identity --profile "$AWS_PROFILE" &> /dev/null; then
            print_error "AWS CLI is not configured or session expired."
            print_error "Please run 'aws sso login' to authenticate with AWS SSO."
            exit 1
        fi
    else
        if ! aws sts get-caller-identity &> /dev/null; then
            print_error "AWS CLI is not configured or session expired."
            print_error "Please run 'aws sso login' to authenticate with AWS SSO."
            exit 1
        fi
    fi
    print_always "AWS authentication verified"
}

# ログディレクトリの作成
ensure_logs_dir() {
    if [ ! -d "$LOGS_DIR" ]; then
        if mkdir -p "$LOGS_DIR" 2>/dev/null; then
            print_status "Created logs directory: $LOGS_DIR"
        else
            print_warning "Could not create logs directory: $LOGS_DIR (read-only filesystem). Logging will be disabled."
            LOGS_DIR=""
        fi
    fi
}

# 設定の検証
validate_config() {
    print_progress "Validating configuration" 2
    
    ensure_logs_dir
    check_dependencies
    check_aws_auth
    
    print_always "Configuration validation passed"
}

# 共通の初期化処理
init_common() {
    ensure_logs_dir
    validate_config
}

# ECSクラスター名の取得
get_ecs_cluster_name() {
    if [ -n "$CLUSTER_NAME" ]; then
        print_debug "Using cluster from environment: $CLUSTER_NAME"
        return 0
    fi
    
    print_status "Detecting ECS cluster..."
    if ! CLUSTER_NAME=$(./scripts/resource_detector.sh cluster); then
        print_error "Failed to detect ECS cluster"
        exit 1
    fi
    print_success "Found ECS cluster: $CLUSTER_NAME"
}

# ECSサービス名の取得
get_ecs_service_name() {
    if [ -n "$SERVICE_NAME" ]; then
        print_debug "Using service from environment: $SERVICE_NAME"
        return 0
    fi
    
    print_status "Detecting ECS service..."
    if ! SERVICE_NAME=$(./scripts/resource_detector.sh service "$CLUSTER_NAME"); then
        print_error "Failed to detect ECS service"
        exit 1
    fi
    print_success "Found ECS service: $SERVICE_NAME"
}

# ECSコンテナ名の取得
get_container_name() {
    print_status "Detecting container name..."
    set +e
    local detector_output
    detector_output=$(./scripts/resource_detector.sh container "$CLUSTER_NAME" "$TASK_ARN" 2>&1)
    local detector_exit_code=$?
    set -e

    if [ $detector_exit_code -eq 0 ]; then
        CONTAINER_NAME=$(echo "$detector_output" | grep -v '^\[' | tail -1)
    else
        print_error "Failed to detect container name: $detector_output"
        exit 1
    fi

    if [ -n "$CONTAINER_NAME" ]; then
        print_success "Found container: $CONTAINER_NAME"
    else
        print_error "Failed to detect container name"
        exit 1
    fi
}

# 現在実行中のタスクARNの取得
get_task_arn() {
    if [ -n "$TASK_ARN" ]; then
        print_debug "Using task ARN from environment: $TASK_ARN"
        return 0
    fi
    
    print_status "Detecting running task..."
    if ! TASK_ARN=$(./scripts/resource_detector.sh task "$CLUSTER_NAME" "$SERVICE_NAME"); then
        print_error "Failed to detect running task"
        exit 1
    fi
    print_success "Found running task: $(basename "$TASK_ARN")"
}

# タスクの状態チェック
check_task_status() {
    print_status "Checking task status..."
    local status=$(aws ecs describe-tasks \
        --cluster "$CLUSTER_NAME" \
        --tasks "$TASK_ARN" \
        --query 'tasks[0].lastStatus' \
        --output text \
        --region "$AWS_REGION")
    
    if [ "$status" != "RUNNING" ]; then
        print_error "Task is not running. Current status: $status"
        exit 1
    fi
    
    print_success "Task is running"
}

# RCON設定の取得
get_rcon_config() {
    print_status "Getting RCON configuration..."
    
    local task_def_arn=$(aws ecs describe-tasks \
        --cluster "$CLUSTER_NAME" \
        --tasks "$TASK_ARN" \
        --query 'tasks[0].taskDefinitionArn' \
        --output text \
        --region "$AWS_REGION")
    
    local rcon_port=$(aws ecs describe-task-definition \
        --task-definition "$task_def_arn" \
        --query 'taskDefinition.containerDefinitions[0].environment[?name==`RCON_PORT`].value' \
        --output text \
        --region "$AWS_REGION")
    
    local rcon_password=$(aws ecs describe-task-definition \
        --task-definition "$task_def_arn" \
        --query 'taskDefinition.containerDefinitions[0].environment[?name==`RCON_PASSWORD`].value' \
        --output text \
        --region "$AWS_REGION")
    
    RCON_PORT="${rcon_port:-25575}"
    RCON_PASSWORD="${rcon_password:-minecraft123}"
    
    print_success "RCON configuration: port=$RCON_PORT, password=***"
}

# RCONコマンドの実行
execute_rcon_command() {
    local command="$1"
    print_status "Executing RCON command: $command"
    
    get_rcon_config
    
    aws ecs execute-command \
        --cluster "$CLUSTER_NAME" \
        --task "$TASK_ARN" \
        --container "$CONTAINER_NAME" \
        --interactive \
        --command "rcon-cli --host localhost --port $RCON_PORT --password $RCON_PASSWORD $command" \
        --region "$AWS_REGION"
}

# プレイヤーリストの取得
list_players() {
    print_status "Getting player list..."
    execute_rcon_command "list"
}

# サーバー情報の取得
get_server_info() {
    print_status "Getting server info..."
    execute_rcon_command "info"
}

# プレイヤーへのメッセージ送信
send_message() {
    local message="$1"
    if [ -z "$message" ]; then
        print_error "Message is required. Usage: send_message \"Your message here\""
        return 1
    fi
    print_status "Sending message: $message"
    execute_rcon_command "say $message"
}

# カスタムRCONコマンドの実行
execute_custom_rcon() {
    local command="$1"
    if [ -z "$command" ]; then
        print_error "Command is required. Usage: execute_custom_rcon \"your command here\""
        return 1
    fi
    execute_rcon_command "$command"
}

# インタラクティブシェルの開始
open_shell() {
    print_status "Opening interactive shell..."
    print_warning "Note: Use 'exit' to return to the host shell"
    
    aws ecs execute-command \
        --cluster "$CLUSTER_NAME" \
        --task "$TASK_ARN" \
        --container "$CONTAINER_NAME" \
        --interactive \
        --command "/bin/bash" \
        --region "$AWS_REGION"
}

# サーバーログの表示
show_server_logs() {
    local lines="${1:-50}"
    print_status "Showing last $lines lines of server logs..."
    
    # タスク定義からロググループ名を動的に取得
    local task_def_arn=$(aws ecs describe-tasks \
        --cluster "$CLUSTER_NAME" \
        --tasks "$TASK_ARN" \
        --query 'tasks[0].taskDefinitionArn' \
        --output text \
        --region "$AWS_REGION")
    
    local log_group_name=$(aws ecs describe-task-definition \
        --task-definition "$task_def_arn" \
        --query 'taskDefinition.containerDefinitions[0].logConfiguration.options."awslogs-group"' \
        --output text \
        --region "$AWS_REGION")
    
    if [ "$log_group_name" = "None" ] || [ -z "$log_group_name" ]; then
        print_error "Could not determine log group name from task definition"
        return 1
    fi
    
    print_status "Using log group: $log_group_name"
    
    # Minecraftコンテナのログストリームを取得（ECS Execute Commandのログを除外）
    local log_stream=$(aws logs describe-log-streams \
        --log-group-name "$log_group_name" \
        --order-by LastEventTime \
        --descending \
        --query 'logStreams[?contains(logStreamName, `container`)].logStreamName' \
        --output text \
        --region "$AWS_REGION" | head -1)
    
    if [ "$log_stream" = "None" ] || [ -z "$log_stream" ]; then
        print_error "No log streams found in log group: $log_group_name"
        return 1
    fi
    
    print_status "Log stream: $log_stream"
    
    aws logs get-log-events \
        --log-group-name "$log_group_name" \
        --log-stream-name "$log_stream" \
        --limit "$lines" \
        --query 'events[].message' \
        --output text \
        --region "$AWS_REGION"
}

# タスクの状態表示
show_task_status() {
    print_status "Task Status:"
    aws ecs describe-tasks \
        --cluster "$CLUSTER_NAME" \
        --tasks "$TASK_ARN" \
        --query 'tasks[0].{Status:lastStatus,Health:healthStatus,CPU:cpu,Memory:memory,StartedAt:createdAt}' \
        --output table \
        --region "$AWS_REGION"
}

# インタラクティブシェルの開始
open_shell() {
    print_status "Opening interactive shell to container: $CONTAINER_NAME"
    print_status "Task ARN: $TASK_ARN"
    print_status "Cluster: $CLUSTER_NAME"
    echo ""
    print_warning "Note: Use 'exit' to close the shell session"
    echo ""
    
    aws ecs execute-command \
        --cluster "$CLUSTER_NAME" \
        --task "$TASK_ARN" \
        --container "$CONTAINER_NAME" \
        --interactive \
        --command "/bin/bash" \
        --region "$AWS_REGION"
}

# ECSの初期化
init_ecs() {
    get_ecs_cluster_name
    get_ecs_service_name
    get_task_arn
    get_container_name
    check_task_status
}

# ヘルプの表示
show_help() {
    echo "Minecraft ECS Exec Script"
    echo ""
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  list                    Show online players"
    echo "  info                    Show server information"
    echo "  message \"text\"         Send message to all players"
    echo "  rcon \"command\"         Execute custom RCON command"
    echo "  shell                   Open interactive shell"
    echo "  logs [lines]            Show server logs (default: 50 lines)"
    echo "  status                  Show task status"
    echo "  help                    Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 list                              # Show online players"
    echo "  $0 message \"Hello everyone!\"        # Send message to players"
    echo "  $0 rcon \"weather clear\"             # Set weather to clear"
    echo "  $0 rcon \"time set day\"              # Set time to day"
    echo "  $0 rcon \"gamemode creative @a\"      # Set all players to creative mode"
    echo "  $0 shell                             # Open interactive shell"
    echo "  $0 logs 100                          # Show last 100 log lines"
    echo ""
    echo "Environment Variables:"
    echo "  LOG_LEVEL=0                  # ERROR only (default)"
    echo "  LOG_LEVEL=1                  # WARNING+"
    echo "  LOG_LEVEL=2                  # INFO+ (verbose)"
    echo "  LOG_LEVEL=3                  # DEBUG+ (debug mode)"
    echo ""
    echo "Debug Examples:"
    echo "  LOG_LEVEL=2 $0 list          # Verbose mode"
    echo "  LOG_LEVEL=3 $0 rcon \"list\"  # Debug mode"
}

# 使用方法の表示
print_usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  list                    List online players"
    echo "  info                    Get server information"
    echo "  message <text>          Send message to all players"
    echo "  rcon <command>          Execute custom RCON command"
    echo "  shell                   Open interactive shell to container"
    echo "  logs [lines]            Show server logs (default: 50 lines)"
    echo "  status                  Show task status"
    echo "  help                    Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 list                 # List online players"
    echo "  $0 message 'Hello!'     # Send message to all players"
    echo "  $0 rcon 'time set day'  # Execute RCON command"
    echo "  $0 logs 100             # Show last 100 lines of logs"
}

# メイン関数
main() {
    local command="${1:-help}"
    
    # helpコマンドの場合は初期化処理をスキップ
    if [ "$command" = "help" ] || [ "$command" = "--help" ] || [ "$command" = "-h" ]; then
        print_usage
        return 0
    fi
    
    # リソース検出
    detect_resources
    
    # 共通の初期化処理
    init_common
    
    # ECSの初期化（RCONコマンドの場合のみ）
    case "$command" in
        list|info|message|rcon|shell|logs|status)
            init_ecs
            ;;
    esac
    
    case "$command" in
        list)
            list_players
            ;;
        info)
            get_server_info
            ;;
        message)
            send_message "$2"
            ;;
        rcon)
            execute_custom_rcon "$2"
            ;;
        shell)
            open_shell
            ;;
        logs)
            show_server_logs "$2"
            ;;
        status)
            show_task_status
            ;;
        *)
            print_error "Unknown command: $command"
            print_usage
            exit 1
            ;;
    esac
}

# メイン関数の実行
main "$@"