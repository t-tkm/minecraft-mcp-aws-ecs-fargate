#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

# =============================================================================
# Minecraft Manager - ポートフォワード管理スクリプト
# =============================================================================
# UC1: ポートフォワード管理のみ（UC2はClaude Desktopが自動起動）

# スクリプトの基本設定
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 環境変数の読み込み
if [ -f "$PROJECT_ROOT/.env" ]; then
    set -a
    source "$PROJECT_ROOT/.env"
    set +a
    echo "[DEBUG] Environment variables loaded from .env" >&2
else
    echo "[WARNING] .env file not found. Please create .env file from env.example" >&2
fi

# ログディレクトリ設定
LOGS_DIR="${LOGS_DIR:-$PROJECT_ROOT/logs}"

# ログレベル設定
# 0: ERROR only, 1: WARNING+, 2: INFO+, 3: DEBUG+
LOG_LEVEL="${LOG_LEVEL:-0}"

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

# リソース検出（Projectタグベースで自動検出）
# helpコマンドの場合はスキップ
first_arg="${1:-help}"
if [ "$first_arg" != "help" ] && [ "$first_arg" != "--help" ] && [ "$first_arg" != "-h" ]; then
    print_always "Starting Minecraft Manager..."
    if [ -z "${EC2_INSTANCE_ID:-}" ] || [ -z "${NLB_DNS_NAME:-}" ]; then
        print_always "Detecting port forward resources"
        print_progress "Running resource detection" 3
        set +e
        detection_output=$(./scripts/resource_detector.sh port-forward 2>&1)
        detection_exit_code=$?
        set -e
        
        if [ $detection_exit_code -eq 0 ]; then
            # 環境変数設定行のみを抽出
            env_lines=$(echo "$detection_output" | grep "^export ")
            eval "$env_lines"
            print_always "Port forward resource detection completed"
        else
            print_error "Port forward resource detection failed: $detection_output"
            exit 1
        fi
    else
        print_always "Using pre-configured port forward resources"
    fi
fi

# 検出されたリソースを確認（ポートフォワード用のみ）
EC2_INSTANCE_ID="${EC2_INSTANCE_ID:-}"
NLB_DNS_NAME="${NLB_DNS_NAME:-}"

# ポート設定
MINECRAFT_PORT="${MINECRAFT_PORT:-25565}"
RCON_PORT="${RCON_PORT:-25575}"

# PIDファイルの場所
MINECRAFT_PID_FILE="$LOGS_DIR/minecraft-port-forward.pid"
RCON_PID_FILE="$LOGS_DIR/rcon-port-forward.pid"

# ログファイルの場所
MINECRAFT_LOG_FILE="$LOGS_DIR/minecraft-port-forward.log"
RCON_LOG_FILE="$LOGS_DIR/rcon-port-forward.log"

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
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS CLI is not configured or session expired."
        print_error "Please run 'aws sso login' to authenticate with AWS SSO."
        exit 1
    fi
    print_always "AWS authentication verified"
}

# ログディレクトリの作成
ensure_logs_dir() {
    if [ ! -d "$LOGS_DIR" ]; then
        mkdir -p "$LOGS_DIR"
        print_status "Created logs directory: $LOGS_DIR"
    fi
}

# プロセスが実行中かチェック
is_process_running() {
    local pid_file="$1"
    local process_name="$2"
    
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            return 0
        else
            print_warning "$process_name: STOPPED (PID file exists but process not running)"
            rm -f "$pid_file"
            return 1
        fi
    else
        print_warning "$process_name: NOT RUNNING"
        return 1
    fi
}

# プロセスを安全に停止
stop_process() {
    local pid_file="$1"
    local process_name="$2"
    
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            print_status "Stopping $process_name (PID: $pid)"
            kill "$pid" 2>/dev/null || true
            sleep 2
            
            if kill -0 "$pid" 2>/dev/null; then
                print_warning "Force killing $process_name (PID: $pid)"
                kill -9 "$pid" 2>/dev/null || true
            fi
        fi
        rm -f "$pid_file"
    fi
}

# ポートが使用中かチェック
is_port_in_use() {
    local port="$1"
    lsof -i ":$port" >/dev/null 2>&1
}

# ポートを使用しているプロセスを停止（ユーザー確認付き）
stop_process_on_port() {
    local port="$1"
    local process_name="$2"
    
    if ! is_port_in_use "$port"; then
        return 0
    fi
    
    local port_pid=$(lsof -ti ":$port")
    if [ -n "$port_pid" ]; then
        local process_info=$(ps -p "$port_pid" -o comm= 2>/dev/null || echo "")
        local process_args=$(ps -p "$port_pid" -o args= 2>/dev/null || echo "")
        
        print_warning "Port $port is in use by another process:"
        print_warning "  PID: $port_pid"
        print_warning "  Command: $process_info"
        
        # AWS SSMセッションの詳細情報を表示
        if [[ "$process_info" == *"session-manager-plugin"* ]]; then
            local session_id=$(echo "$process_args" | grep -o '"SessionId":"[^"]*"' | cut -d'"' -f4 || echo "unknown")
            local target=$(echo "$process_args" | grep -o '"Target":"[^"]*"' | cut -d'"' -f4 || echo "unknown")
            local local_port=$(echo "$process_args" | grep -o '"localPortNumber":"[^"]*"' | cut -d'"' -f4 || echo "unknown")
            
            print_warning "  Session ID: $session_id"
            print_warning "  Target: $target"
            print_warning "  Local Port: $local_port"
        fi
        
        echo ""
        print_warning "This process needs to be stopped to start the new port forward."
        print_warning "If you choose 'y', the existing process will be terminated and a new port forward will be started."
        echo -n "Do you want to stop the existing process and start a new port forward? (y/N): "
        read -r response
        
        if [[ "$response" =~ ^[Yy]$ ]]; then
            print_status "Stopping existing process..."
            
            if [[ "$process_info" == *"session-manager-plugin"* ]] || [[ "$process_info" == *"aws"* ]]; then
                print_warning "Detected AWS SSM session process. Attempting graceful termination..."
                
                if [ -n "$session_id" ] && [ "$session_id" != "unknown" ]; then
                    print_status "Terminating AWS SSM session: $session_id"
                    aws ssm terminate-session --session-id "$session_id" --region "$AWS_REGION" >/dev/null 2>&1
                    sleep 3
                fi
            fi
            
            if kill -0 "$port_pid" 2>/dev/null; then
                print_warning "Process still running, trying graceful kill..."
                kill "$port_pid" 2>/dev/null || true
                sleep 2
                
                if kill -0 "$port_pid" 2>/dev/null; then
                    print_warning "Process still running, trying force kill..."
                    kill -9 "$port_pid" 2>/dev/null || true
                    sleep 1
                fi
            fi
            
            if ! is_port_in_use "$port"; then
                print_success "Successfully freed port $port"
                return 0
            else
                print_error "Failed to free port $port. Please stop the process manually."
                return 1
            fi
        else
            print_error "Port $port is still in use. Cannot start port forward."
            return 1
        fi
    else
        print_error "Could not find process using port $port. Please stop it manually."
        return 1
    fi
}

# ポートを使用しているプロセスを停止（自動モード - 確認なし）
stop_process_on_port_auto() {
    local port="$1"
    local process_name="$2"
    
    if ! is_port_in_use "$port"; then
        return 0
    fi
    
    local port_pid=$(lsof -ti ":$port")
    if [ -n "$port_pid" ]; then
        local process_info=$(ps -p "$port_pid" -o comm= 2>/dev/null || echo "")
        local process_args=$(ps -p "$port_pid" -o args= 2>/dev/null || echo "")
        
        print_status "Stopping existing process on port $port (PID: $port_pid)..."
        
        # AWS SSMセッションの詳細情報を取得
        if [[ "$process_info" == *"session-manager-plugin"* ]]; then
            local session_id=$(echo "$process_args" | grep -o '"SessionId":"[^"]*"' | cut -d'"' -f4 || echo "unknown")
            
            if [[ "$process_info" == *"session-manager-plugin"* ]] || [[ "$process_info" == *"aws"* ]]; then
                print_debug "Detected AWS SSM session process. Attempting graceful termination..."
                
                if [ -n "$session_id" ] && [ "$session_id" != "unknown" ]; then
                    print_debug "Terminating AWS SSM session: $session_id"
                    aws ssm terminate-session --session-id "$session_id" --region "$AWS_REGION" >/dev/null 2>&1
                    sleep 3
                fi
            fi
        fi
        
        if kill -0 "$port_pid" 2>/dev/null; then
            print_debug "Process still running, trying graceful kill..."
            kill "$port_pid" 2>/dev/null || true
            sleep 2
            
            if kill -0 "$port_pid" 2>/dev/null; then
                print_debug "Process still running, trying force kill..."
                kill -9 "$port_pid" 2>/dev/null || true
                sleep 1
            fi
        fi
        
        if ! is_port_in_use "$port"; then
            print_success "Successfully freed port $port"
            return 0
        else
            print_error "Failed to free port $port. Please stop the process manually."
            return 1
        fi
    else
        print_error "Could not find process using port $port. Please stop it manually."
        return 1
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

# EC2インスタンスIDの取得
get_ec2_instance_id() {
    if [ -n "$EC2_INSTANCE_ID" ]; then
        print_debug "Using EC2 instance from environment: $EC2_INSTANCE_ID"
        return 0
    fi
    
    print_status "Detecting EC2 instance... (this may take a few seconds)"
    if ! EC2_INSTANCE_ID=$(./scripts/resource_detector.sh ec2); then
        print_error "Failed to detect EC2 instance"
        exit 1
    fi
    print_success "Found EC2 instance: $EC2_INSTANCE_ID"
}

# NLB DNS名の取得
get_nlb_dns_name() {
    if [ -n "$NLB_DNS_NAME" ]; then
        print_debug "Using NLB DNS from environment: $NLB_DNS_NAME"
        return 0
    fi
    
    print_status "Detecting NLB DNS name... (this may take a few seconds)"
    if ! NLB_DNS_NAME=$(./scripts/resource_detector.sh nlb); then
        print_error "Failed to detect NLB DNS name"
        exit 1
    fi
    print_success "Found NLB DNS: $NLB_DNS_NAME"
}

# Minecraftポートフォワードの開始
start_minecraft_port_forward() {
    local auto_mode="${1:-false}"
    
    print_status "Starting Minecraft port forward (port $MINECRAFT_PORT)..."
    
    if is_port_in_use "$MINECRAFT_PORT"; then
        if is_process_running "$MINECRAFT_PID_FILE" "Minecraft port forward"; then
            print_debug "Port $MINECRAFT_PORT is already in use by our process"
            return 0
        else
            if [ "$auto_mode" = "true" ]; then
                print_debug "Port $MINECRAFT_PORT is in use by another process - stopping automatically"
                stop_process_on_port_auto "$MINECRAFT_PORT" "Minecraft"
            else
                print_debug "Port $MINECRAFT_PORT is in use by another process"
                if ! stop_process_on_port "$MINECRAFT_PORT" "Minecraft"; then
                    return 1
                fi
            fi
        fi
    fi
    
    stop_process "$MINECRAFT_PID_FILE" "Minecraft port forward"
    
    nohup aws ssm start-session \
        --target "$EC2_INSTANCE_ID" \
        --document-name AWS-StartPortForwardingSessionToRemoteHost \
        --parameters "{\"host\":[\"$NLB_DNS_NAME\"],\"portNumber\":[\"$MINECRAFT_PORT\"],\"localPortNumber\":[\"$MINECRAFT_PORT\"]}" \
        --region "$AWS_REGION" > "$MINECRAFT_LOG_FILE" 2>&1 &
    
    local minecraft_pid=$!
    echo "$minecraft_pid" > "$MINECRAFT_PID_FILE"
    disown $minecraft_pid
    
    sleep 3
    if kill -0 "$minecraft_pid" 2>/dev/null; then
        print_success "Minecraft port forward started (PID: $minecraft_pid)"
        print_status "Minecraft server will be available at localhost:$MINECRAFT_PORT"
    else
        print_error "Failed to start Minecraft port forward"
        rm -f "$MINECRAFT_PID_FILE"
        return 1
    fi
}

# RCONポートフォワードの開始
start_rcon_port_forward() {
    local auto_mode="${1:-false}"
    
    print_status "Starting RCON port forward (port $RCON_PORT)..."
    
    if is_port_in_use "$RCON_PORT"; then
        if is_process_running "$RCON_PID_FILE" "RCON port forward"; then
            print_debug "Port $RCON_PORT is already in use by our process"
            return 0
        else
            if [ "$auto_mode" = "true" ]; then
                print_debug "Port $RCON_PORT is in use by another process - stopping automatically"
                stop_process_on_port_auto "$RCON_PORT" "RCON"
            else
                print_debug "Port $RCON_PORT is in use by another process"
                if ! stop_process_on_port "$RCON_PORT" "RCON"; then
                    return 1
                fi
            fi
        fi
    fi
    
    stop_process "$RCON_PID_FILE" "RCON port forward"
    
    nohup aws ssm start-session \
        --target "$EC2_INSTANCE_ID" \
        --document-name AWS-StartPortForwardingSessionToRemoteHost \
        --parameters "{\"host\":[\"$NLB_DNS_NAME\"],\"portNumber\":[\"$RCON_PORT\"],\"localPortNumber\":[\"$RCON_PORT\"]}" \
        --region "$AWS_REGION" > "$RCON_LOG_FILE" 2>&1 &
    
    local rcon_pid=$!
    echo "$rcon_pid" > "$RCON_PID_FILE"
    disown $rcon_pid
    
    sleep 3
    if kill -0 "$rcon_pid" 2>/dev/null; then
        print_success "RCON port forward started (PID: $rcon_pid)"
        print_status "RCON will be available at localhost:$RCON_PORT"
    else
        print_error "Failed to start RCON port forward"
        rm -f "$RCON_PID_FILE"
        return 1
    fi
}

# ポート競合を事前チェック
check_port_conflicts() {
    local conflicts_found=false
    
    if is_port_in_use "$MINECRAFT_PORT"; then
        print_warning "Port $MINECRAFT_PORT (Minecraft) is already in use"
        conflicts_found=true
    fi
    
    if is_port_in_use "$RCON_PORT"; then
        print_warning "Port $RCON_PORT (RCON) is already in use"
        conflicts_found=true
    fi
    
    if [ "$conflicts_found" = true ]; then
        echo ""
        print_warning "Port conflicts detected. The script will ask for confirmation to stop existing processes."
        print_warning "If you choose 'y', existing port forward sessions will be stopped and new ones will be started."
        echo -n "Do you want to stop existing processes and start new port forwards? (y/N): "
        read -r response
        
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            print_error "Port forward start cancelled by user"
            return 1
        fi
    fi
    
    return 0
}

# 全ポートフォワードの開始
start_all_port_forwards() {
    print_status "Starting Minecraft SSM port forwards..."
    
    # ポート競合を事前チェック
    if ! check_port_conflicts; then
        return 1
    fi
    
    get_ec2_instance_id
    get_nlb_dns_name
    
    # ポート競合の確認が完了したので、自動停止モードで開始
    if ! start_minecraft_port_forward true; then
        return 1
    fi
    if ! start_rcon_port_forward true; then
        return 1
    fi
    
    print_success "All port forwards started successfully!"
    print_status "You can now connect to:"
    print_status "  Minecraft server: localhost:$MINECRAFT_PORT"
    print_status "  RCON: localhost:$RCON_PORT"
}

# 全ポートフォワードの停止
stop_all_port_forwards() {
    print_status "Stopping all port forward sessions..."
    
    stop_process "$MINECRAFT_PID_FILE" "Minecraft port forward"
    stop_process "$RCON_PID_FILE" "RCON port forward"
    
    cleanup_orphaned_sessions
    
    print_success "All port forward sessions stopped"
}

# 孤立したAWS SSMセッションのクリーンアップ
cleanup_orphaned_sessions() {
    print_status "Cleaning up orphaned AWS SSM sessions... (this may take a few seconds)"
    
    if [ -z "$EC2_INSTANCE_ID" ]; then
        local instances_json=$(aws ec2 describe-instances \
            --filters "Name=instance-state-name,Values=running" \
            --query 'Reservations[].Instances[].[InstanceId,Tags[?Key==`Name`].Value|[0]]' \
            --output json \
            --region "$AWS_REGION" 2>/dev/null)
        
        local filtered_instances=$(echo "$instances_json" | jq '[.[] | select(.[1] | ascii_downcase | contains("minecraft") and contains("proxy"))]')
        local instance_count=$(echo "$filtered_instances" | jq length)
        
        if [ "$instance_count" -eq 1 ]; then
            EC2_INSTANCE_ID=$(echo "$filtered_instances" | jq -r '.[0][0]')
        else
            print_warning "Could not determine EC2 instance ID for cleanup"
            return
        fi
    fi
    
    local active_sessions
    active_sessions=$(aws ssm describe-sessions \
        --state "Active" \
        --region "$AWS_REGION" \
        --query "Sessions[?Target=='$EC2_INSTANCE_ID' && DocumentName=='AWS-StartPortForwardingSessionToRemoteHost'].SessionId" \
        --output text 2>/dev/null)
    
    if [ -n "$active_sessions" ]; then
        print_status "Found active SSM sessions for EC2 instance $EC2_INSTANCE_ID"
        for session_id in $active_sessions; do
            print_status "Terminating SSM session: $session_id"
            aws ssm terminate-session --session-id "$session_id" --region "$AWS_REGION" >/dev/null 2>&1 || true
        done
    fi
}

# ポートフォワードの状態表示
show_port_forward_status() {
    print_status "Port forward status:"
    
    if is_process_running "$MINECRAFT_PID_FILE" "Minecraft port forward"; then
        local minecraft_pid=$(cat "$MINECRAFT_PID_FILE")
        print_success "Minecraft port forward: RUNNING (PID: $minecraft_pid)"
    fi
    
    if is_process_running "$RCON_PID_FILE" "RCON port forward"; then
        local rcon_pid=$(cat "$RCON_PID_FILE")
        print_success "RCON port forward: RUNNING (PID: $rcon_pid)"
    fi
}

# ポートフォワードのログ表示
show_port_forward_logs() {
    local service="$1"
    
    case "$service" in
        minecraft)
            if [ -f "$MINECRAFT_LOG_FILE" ]; then
                print_status "Minecraft port forward logs:"
                tail -n 20 "$MINECRAFT_LOG_FILE"
            else
                print_warning "No Minecraft port forward logs found"
            fi
            ;;
        rcon)
            if [ -f "$RCON_LOG_FILE" ]; then
                print_status "RCON port forward logs:"
                tail -n 20 "$RCON_LOG_FILE"
            else
                print_warning "No RCON port forward logs found"
            fi
            ;;
        *)
            print_error "Usage: show_port_forward_logs [minecraft|rcon]"
            return 1
            ;;
    esac
}

# 状態表示
show_status() {
    if is_port_in_use "$MINECRAFT_PORT"; then
        print_success "Minecraft Client port ($MINECRAFT_PORT) forwarding: ACTIVE"
    else
        print_warning "Minecraft Client port ($MINECRAFT_PORT) forwarding: INACTIVE"
    fi
    
    if is_port_in_use "$RCON_PORT"; then
        print_success "RCON CLI port ($RCON_PORT) forwarding: ACTIVE"
    else
        print_warning "RCON CLI port ($RCON_PORT) forwarding: INACTIVE"
    fi
    
    echo ""
    print_status "Claude Desktop will automatically start MCP server when needed"
}

# ポートフォワードの開始
start_port_forward() {
    if start_all_port_forwards; then
        print_success "Port forwarding started successfully!"
        print_status ""
        print_status "To stop port forwards, run: $0 stop"
        print_status "To check status, run: $0 status"
    else
        print_error "Failed to start port forwarding"
        return 1
    fi
}

# ポートフォワードの停止
stop_port_forward() {
    stop_all_port_forwards
    print_success "Port forwarding stopped successfully!"
}

# ポートフォワードの再起動
restart_port_forward() {
    print_status "Stopping existing port forwards..."
    stop_all_port_forwards
    sleep 2
    print_status "Starting new port forwards..."
    if start_all_port_forwards; then
        print_success "Port forwarding restarted successfully!"
    else
        print_error "Failed to restart port forwarding"
        return 1
    fi
}

# ヘルプの表示
show_help() {
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  status              Show port forwarding status"
    echo "  start               Start port forwarding for Minecraft server access"
    echo "  stop                Stop port forwarding"
    echo "  restart             Restart port forwarding"
    echo "  help                Show this help message"
    echo ""
    echo "Use Cases:"
    echo "  Minecraft Server Access -> localhost:$MINECRAFT_PORT (Minecraft Client) + localhost:$RCON_PORT (RCON CLI)"
    echo "  Claude Desktop -> MCP Server -> AWS ECS EXEC -> ECS Service"
    echo ""
    echo "Examples:"
    echo "  $0 status                    # Show port forwarding status"
    echo "  $0 start                     # Start port forwarding"
    echo "  $0 restart                   # Restart port forwarding"
    echo ""
    echo "Environment Variables:"
    echo "  LOG_LEVEL=0                  # ERROR only (default: 1)"
    echo "  LOG_LEVEL=1                  # WARNING+ (default)"
    echo "  LOG_LEVEL=2                  # INFO+ (verbose)"
    echo "  LOG_LEVEL=3                  # DEBUG+ (debug mode)"
    echo ""
    echo "Debug Examples:"
    echo "  LOG_LEVEL=2 $0 start         # Verbose mode"
    echo "  LOG_LEVEL=3 $0 start         # Debug mode"
}

# メイン関数
main() {
    local command="${1:-help}"
    
    case "$command" in
        status)
            print_status "Checking port forwarding status..."
            init_common
            show_status
            ;;
        start)
            print_status "Starting port forwarding..."
            init_common
            start_port_forward
            ;;
        stop)
            print_status "Stopping port forwarding..."
            init_common
            stop_port_forward
            ;;
        restart)
            print_status "Restarting port forwarding..."
            init_common
            restart_port_forward
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            print_error "Unknown command: $command"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# メイン関数の実行
main "$@"