#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

# =============================================================================
# リソース検出関数ライブラリ - Projectタグベース
# minecraft-manager.shやecs-exec.shから関数として呼び出される
# =============================================================================

# スクリプトの基本設定
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 環境変数の読み込み
if [ -f "$PROJECT_ROOT/.env" ]; then
    set -a
    source "$PROJECT_ROOT/.env"
    set +a
fi

# 設定値（環境変数が必須）
ENVIRONMENT="${ENVIRONMENT}"
PROJECT_NAME="${PROJECT_NAME}"
AWS_REGION="${AWS_REGION}"

# 環境変数の必須チェック
validate_environment_variables() {
    [ -z "${ENVIRONMENT:-}" ] && { echo "ERROR: ENVIRONMENT not set" >&2; return 1; }
    [ -z "${PROJECT_NAME:-}" ] && { echo "ERROR: PROJECT_NAME not set" >&2; return 1; }
    [ -z "${AWS_REGION:-}" ] && { echo "ERROR: AWS_REGION not set" >&2; return 1; }
    return 0
}

# jq出力フィルタリング関数
filter_jq_output() {
    local line
    while IFS= read -r line; do
        [[ "$line" == jq\ * ]] && continue
        [[ -z "$line" ]] && continue
        printf '%s\n' "$line"
    done
}

has_project_tag() {
    local tags_json="$1"

    if [ -z "$tags_json" ] || [ "$tags_json" = "null" ]; then
        return 1
    fi

    jq -e --arg project "$PROJECT_NAME" '
        .[]
        | select((.key // .Key) == "Project" and (.value // .Value) == $project)
    ' <<<"$tags_json" >/dev/null 2>&1
}


# 依存関係チェック
check_dependencies() {
    command -v aws >/dev/null || { echo "ERROR: aws command not found" >&2; exit 1; }
    command -v jq >/dev/null || { echo "ERROR: jq command not found" >&2; exit 1; }
}

# AWS認証チェック
check_aws_auth() {
    aws sts get-caller-identity >/dev/null 2>&1 || { echo "ERROR: AWS authentication failed" >&2; exit 1; }
}

# ECSクラスターを検出（Projectタグベース）
detect_ecs_cluster() {
    local tagged_clusters
    tagged_clusters=$(aws ecs list-clusters \
        --query "clusterArns" \
        --output json \
        --region "$AWS_REGION" 2>/dev/null | \
        jq -r '.[]' 2>/dev/null | filter_jq_output) || return 1
    
    for cluster_arn in $tagged_clusters; do
        local cluster_name=$(echo "$cluster_arn" | sed 's/.*\///')
        local cluster_tags=$(aws ecs describe-clusters \
            --clusters "$cluster_name" \
            --include TAGS \
            --query "clusters[0].tags" \
            --output json \
            --region "$AWS_REGION" 2>/dev/null) || return 1
        
        if has_project_tag "$cluster_tags"; then
            echo "$cluster_name"
            return 0
        fi
    done
    
    echo "ERROR: ECS cluster not found for project '$PROJECT_NAME'" >&2
    return 1
}

# ECSサービスを検出（Projectタグベース）
detect_ecs_service() {
    local cluster_name="$1"
    local all_services
    all_services=$(aws ecs list-services \
        --cluster "$cluster_name" \
        --query "serviceArns" \
        --output json \
        --region "$AWS_REGION" 2>/dev/null | \
        jq -r '.[]' 2>/dev/null | filter_jq_output) || return 1
    
    for service_arn in $all_services; do
        local service_name=$(echo "$service_arn" | sed 's/.*\///')
        local service_tags=$(aws ecs describe-services \
            --cluster "$cluster_name" \
            --services "$service_name" \
            --include TAGS \
            --query "services[0].tags" \
            --output json \
            --region "$AWS_REGION" 2>/dev/null) || return 1
        
        if has_project_tag "$service_tags"; then
            echo "$service_name"
            return 0
        fi
    done
    
    echo "ERROR: ECS service not found for project '$PROJECT_NAME' in cluster '$cluster_name'" >&2
    return 1
}

# 実行中のタスクARNを検出
detect_task_arn() {
    local cluster_name="$1"
    local service_name="$2"
    
    local task_arn=$(aws ecs list-tasks \
        --cluster "$cluster_name" \
        --service-name "$service_name" \
        --query "taskArns[0]" \
        --output text \
        --region "$AWS_REGION" 2>/dev/null) || return 1
    
    if [ "$task_arn" != "None" ] && [ -n "$task_arn" ]; then
        echo "$task_arn"
        return 0
    else
        echo "ERROR: No running tasks found for service $service_name" >&2
        return 1
    fi
}

# コンテナ名を検出
detect_container_name() {
    local cluster_name="$1"
    local task_arn="$2"
    
    local containers_json=$(aws ecs describe-tasks \
        --cluster "$cluster_name" \
        --tasks "$task_arn" \
        --query "tasks[0].containers[].name" \
        --output json \
        --region "$AWS_REGION" 2>/dev/null) || return 1
    
    if [ -n "$containers_json" ] && [ "$containers_json" != "null" ]; then
        # 優先順位1: minecraft関連のコンテナ名（大文字小文字を区別しない）
        local minecraft_containers=$(echo "$containers_json" | jq -r '.[] | select(test("minecraft"; "i"))' 2>/dev/null | filter_jq_output)
        if [ -n "$minecraft_containers" ]; then
            echo "$minecraft_containers" | head -1
            return 0
        fi
        
        # 優先順位2: 最初のコンテナ
        local container_name=$(echo "$containers_json" | jq -r '.[0]' 2>/dev/null | filter_jq_output)
        if [ -n "$container_name" ] && [ "$container_name" != "null" ]; then
            echo "$container_name"
            return 0
        fi
    fi
    
    echo "ERROR: No suitable container found in task" >&2
    return 1
}

# EC2インスタンスを検出（Projectタグベース）
detect_ec2_instance() {
    local instances
    instances=$(aws ec2 describe-instances \
        --filters "Name=instance-state-name,Values=running" "Name=tag:Project,Values=$PROJECT_NAME" \
        --query "Reservations[].Instances[].InstanceId" \
        --output json \
        --region "$AWS_REGION" 2>/dev/null | \
        jq -r '.[]' 2>/dev/null | filter_jq_output) || return 1
    
    if [ -n "$instances" ]; then
        echo "$instances" | head -1
        return 0
    fi
    
    echo "ERROR: EC2 instance not found for project '$PROJECT_NAME'" >&2
    return 1
}

# NLB DNS名を検出（Projectタグベース）
detect_nlb_dns() {
    local all_lbs
    all_lbs=$(aws elbv2 describe-load-balancers \
        --query "LoadBalancers[].{Arn:LoadBalancerArn,Name:LoadBalancerName}" \
        --output json \
        --region "$AWS_REGION" 2>/dev/null) || return 1
    
    if [ -n "$all_lbs" ]; then
        local lb_arns=$(echo "$all_lbs" | jq -r '.[].Arn' 2>/dev/null | filter_jq_output)
        
        for lb_arn in $lb_arns; do
            local lb_tags=$(aws elbv2 describe-tags \
                --resource-arns "$lb_arn" \
                --query "TagDescriptions[0].Tags" \
                --output json \
                --region "$AWS_REGION" 2>/dev/null) || return 1

            if has_project_tag "$lb_tags"; then
                local dns_name=$(aws elbv2 describe-load-balancers \
                    --load-balancer-arns "$lb_arn" \
                    --query "LoadBalancers[0].DNSName" \
                    --output text \
                    --region "$AWS_REGION" 2>/dev/null) || return 1
                
                if [ -n "$dns_name" ] && [ "$dns_name" != "None" ]; then
                    echo "$dns_name"
                    return 0
                fi
            fi
        done
    fi
    
    echo "ERROR: NLB not found for project '$PROJECT_NAME'" >&2
    return 1
}

# ポートフォワード用リソース検出（minecraft-manager.sh用）
detect_port_forward_resources() {
    validate_environment_variables || return 1
    check_dependencies
    check_aws_auth
    
    local ec2_instance_id=$(detect_ec2_instance) || exit 1
    local nlb_dns_name=$(detect_nlb_dns) || exit 1
    
    # 結果を環境変数として設定
    export EC2_INSTANCE_ID="$ec2_instance_id"
    export NLB_DNS_NAME="$nlb_dns_name"
    
    # 環境変数の設定を出力（eval用）
    echo "export EC2_INSTANCE_ID='$ec2_instance_id'"
    echo "export NLB_DNS_NAME='$nlb_dns_name'"
}

# ECS操作用リソース検出（ecs-exec.sh用）
detect_ecs_resources() {
    validate_environment_variables || return 1
    check_dependencies
    check_aws_auth
    
    local cluster_name=$(detect_ecs_cluster) || exit 1
    local service_name=$(detect_ecs_service "$cluster_name") || exit 1
    local task_arn=$(detect_task_arn "$cluster_name" "$service_name") || exit 1
    local container_name=$(detect_container_name "$cluster_name" "$task_arn") || exit 1
    
    # 結果を環境変数として設定
    export CLUSTER_NAME="$cluster_name"
    export SERVICE_NAME="$service_name"
    export CONTAINER_NAME="$container_name"
    export TASK_ARN="$task_arn"
    
    # 環境変数の設定を出力（eval用）
    echo "export CLUSTER_NAME='$cluster_name'"
    echo "export SERVICE_NAME='$service_name'"
    echo "export CONTAINER_NAME='$container_name'"
    echo "export TASK_ARN='$task_arn'"
}

# 全リソースを検出（後方互換性のため維持）
detect_all_resources() {
    validate_environment_variables || return 1
    check_dependencies
    check_aws_auth
    
    local cluster_name=$(detect_ecs_cluster) || exit 1
    local service_name=$(detect_ecs_service "$cluster_name") || exit 1
    local task_arn=$(detect_task_arn "$cluster_name" "$service_name") || exit 1
    local container_name=$(detect_container_name "$cluster_name" "$task_arn") || exit 1
    local ec2_instance_id=$(detect_ec2_instance) || exit 1
    local nlb_dns_name=$(detect_nlb_dns) || exit 1
    
    # 結果を環境変数として設定
    export CLUSTER_NAME="$cluster_name"
    export SERVICE_NAME="$service_name"
    export CONTAINER_NAME="$container_name"
    export TASK_ARN="$task_arn"
    export EC2_INSTANCE_ID="$ec2_instance_id"
    export NLB_DNS_NAME="$nlb_dns_name"
    
    # 環境変数の設定を出力（eval用）
    echo "export CLUSTER_NAME='$cluster_name'"
    echo "export SERVICE_NAME='$service_name'"
    echo "export CONTAINER_NAME='$container_name'"
    echo "export TASK_ARN='$task_arn'"
    echo "export EC2_INSTANCE_ID='$ec2_instance_id'"
    echo "export NLB_DNS_NAME='$nlb_dns_name'"
}

# メイン関数（後方互換性のため）
main() {
    local command="${1:-detect}"
    
    case "$command" in
        port-forward)
            detect_port_forward_resources
            ;;
        ecs)
            detect_ecs_resources
            ;;
        detect)
            detect_all_resources
            ;;
        cluster)
            detect_ecs_cluster
            ;;
        service)
            detect_ecs_service "$2"
            ;;
        task)
            detect_task_arn "$2" "$3"
            ;;
        container)
            detect_container_name "$2" "$3"
            ;;
        ec2)
            detect_ec2_instance
            ;;
        nlb)
            detect_nlb_dns
            ;;
        *)
            echo "ERROR: Unknown command: $command" >&2
            exit 1
            ;;
    esac
}

# メイン関数の実行
main "$@"