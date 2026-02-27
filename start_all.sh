#!/bin/bash
# Golden House - Start All Services
# Start order:
#   1. Git pull all repositories
#   2. !gateway (nginx + auth-service + mongo)
#   3. Wait for gateway healthcheck
#   4. !gateway/monitoring-service
#   5. !gateway/notification-service
#   6. client_service
#   7. apartment_finder
#   8. referal
#   9. Final status

set -euo pipefail

BASE_DIR="$(dirname "$(readlink -f "$0")")"
GATEWAY_DIR="$BASE_DIR/!gateway"
START_TIME=$(date +%s)
FAILED_SERVICES=()
SUCCEEDED_SERVICES=()

# Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
GRAY='\033[0;90m'
NC='\033[0m'

# ----------------------------------------
# Functions
# ----------------------------------------

write_step() {
    echo ""
    echo -e "${CYAN}>> $1${NC}"
}

write_ok() {
    echo -e "   ${GREEN}[OK] $1${NC}"
}

write_fail() {
    echo -e "   ${RED}[FAIL] $1${NC}"
}

write_info() {
    echo -e "   ${YELLOW}$1${NC}"
}

update_repository() {
    local repo_path="$1"
    local repo_name="$2"

    if [ ! -d "$repo_path/.git" ]; then
        write_info "$repo_name - not a git repo, skipping"
        return 0
    fi

    write_info "Git pull $repo_name..."
    local current_dir
    current_dir=$(pwd)
    cd "$repo_path" || return 1

    if ! git fetch --quiet 2>/dev/null; then
        write_fail "git fetch $repo_name"
        cd "$current_dir" || return 1
        return 1
    fi

    if ! git pull --quiet 2>/dev/null; then
        write_fail "git pull $repo_name"
        cd "$current_dir" || return 1
        return 1
    fi

    write_ok "$repo_name updated"
    cd "$current_dir" || return 1
    return 0
}

start_docker_service() {
    local service_path="$1"
    local service_name="$2"

    if [ ! -f "$service_path/docker-compose.yml" ] && [ ! -f "$service_path/docker-compose.yaml" ]; then
        write_fail "$service_name - docker-compose not found in $service_path"
        FAILED_SERVICES+=("$service_name")
        return 1
    fi

    write_info "docker compose up --build -d [$service_name]..."
    local current_dir
    current_dir=$(pwd)
    cd "$service_path" || return 1

    if docker compose up --build -d 2>&1 | while IFS= read -r line; do echo -e "   ${GRAY}$line${NC}"; done; then
        write_ok "$service_name started"
        SUCCEEDED_SERVICES+=("$service_name")
        cd "$current_dir" || return 1
        return 0
    fi

    write_fail "$service_name - docker compose failed"
    FAILED_SERVICES+=("$service_name")
    cd "$current_dir" || return 1
    return 1
}

wait_for_healthy() {
    local container_name="$1"
    local timeout_seconds="${2:-60}"

    write_info "Waiting for healthcheck $container_name (timeout ${timeout_seconds}s)..."
    local elapsed=0
    local health=""
    while [ "$elapsed" -lt "$timeout_seconds" ]; do
        health=$(docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "not_found")
        if [ "$health" = "healthy" ]; then
            write_ok "$container_name - healthy"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done

    write_fail "$container_name - not healthy after ${timeout_seconds}s (current: $health)"
    return 1
}

# ----------------------------------------
# Main
# ----------------------------------------

echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  GOLDEN HOUSE - Start All Services${NC}"
echo -e "${CYAN}  $(date '+%Y-%m-%d %H:%M:%S')${NC}"
echo -e "${CYAN}============================================${NC}"

# -- Step 1: Git pull --
write_step "Step 1/4 - Update repositories"

update_repository "$BASE_DIR" "AnalyticsRepo (root)"
update_repository "$GATEWAY_DIR" "gateway"

# -- Step 2: Gateway --
write_step "Step 2/4 - Start Gateway"

if [ ! -d "$GATEWAY_DIR" ]; then
    write_fail "Gateway directory not found: $GATEWAY_DIR"
    exit 1
fi

if ! start_docker_service "$GATEWAY_DIR" "gateway"; then
    write_fail "Gateway failed to start - aborting (other services depend on it)"
    exit 1
fi

wait_for_healthy "gateway-nginx-1" 60
wait_for_healthy "gateway-auth-service-1" 60

# -- Step 3: Gateway sub-services --
write_step "Step 3/4 - Start gateway sub-services"

start_docker_service "$GATEWAY_DIR/monitoring-service" "monitoring-service" || true
start_docker_service "$GATEWAY_DIR/notification-service" "notification-service" || true

sleep 3

# -- Step 4: Application services --
write_step "Step 4/4 - Start application services"

APP_SERVICES=(
    "client_service"
    "apartment_finder"
    "referal"
)

for svc in "${APP_SERVICES[@]}"; do
    svc_path="$BASE_DIR/$svc"
    if [ -d "$svc_path" ]; then
        start_docker_service "$svc_path" "$svc" || true
    else
        write_info "$svc - directory not found, skipping"
    fi
done

# ----------------------------------------
# Summary
# ----------------------------------------

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
MINUTES=$((ELAPSED / 60))
SECS=$((ELAPSED % 60))

echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  SUMMARY${NC}"
echo -e "${CYAN}============================================${NC}"
echo -e "  Time: ${MINUTES}m ${SECS}s"

if [ ${#SUCCEEDED_SERVICES[@]} -gt 0 ]; then
    echo -e "  ${GREEN}OK (${#SUCCEEDED_SERVICES[@]}):${NC}"
    for svc in "${SUCCEEDED_SERVICES[@]}"; do
        echo -e "    ${GREEN}+ $svc${NC}"
    done
fi

if [ ${#FAILED_SERVICES[@]} -gt 0 ]; then
    echo -e "  ${RED}FAILED (${#FAILED_SERVICES[@]}):${NC}"
    for svc in "${FAILED_SERVICES[@]}"; do
        echo -e "    ${RED}- $svc${NC}"
    done
fi

echo ""
echo -e "${CYAN}=== RUNNING CONTAINERS ===${NC}"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

if [ ${#FAILED_SERVICES[@]} -gt 0 ]; then
    echo ""
    echo -e "${RED}WARNING: Some services failed to start! Check logs above.${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}All services started successfully!${NC}"