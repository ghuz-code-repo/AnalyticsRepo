#!/bin/bash
# ============================================
# init_env.sh — Initialize .env files from examples
# ============================================
# Run this script on a new server BEFORE start_all.sh
#
# Usage:
#   chmod +x init_env.sh
#   ./init_env.sh          # Interactive — copies examples, reminds to edit
#   ./init_env.sh --force  # Overwrite existing .env files
# ============================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORCE=false

if [[ "${1:-}" == "--force" ]]; then
    FORCE=true
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN} Environment Files Initializer${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""

# List of all .env.example → .env mappings
declare -A ENV_FILES=(
    ["!gateway/.env.example"]="!gateway/.env"
    ["!gateway/auth-service/.env.example"]="!gateway/auth-service/.env"
    ["!gateway/monitoring-service/.env.example"]="!gateway/monitoring-service/.env"
    ["!gateway/notification-service/.env.example"]="!gateway/notification-service/.env"
    ["client_service/.env.example"]="client_service/.env"
    ["referal/.env.example"]="referal/.env"
)

CREATED=0
SKIPPED=0
MISSING_EXAMPLE=0

for example in "${!ENV_FILES[@]}"; do
    target="${ENV_FILES[$example]}"
    example_path="$SCRIPT_DIR/$example"
    target_path="$SCRIPT_DIR/$target"

    if [[ ! -f "$example_path" ]]; then
        echo -e "  ${RED}✗${NC} $example — example file not found!"
        ((MISSING_EXAMPLE++))
        continue
    fi

    if [[ -f "$target_path" && "$FORCE" == false ]]; then
        echo -e "  ${YELLOW}⊘${NC} $target — already exists (use --force to overwrite)"
        ((SKIPPED++))
        continue
    fi

    cp "$example_path" "$target_path"
    echo -e "  ${GREEN}✓${NC} $target — created from example"
    ((CREATED++))
done

echo ""
echo -e "${CYAN}============================================${NC}"
echo -e "  Created: ${GREEN}${CREATED}${NC}"
echo -e "  Skipped: ${YELLOW}${SKIPPED}${NC}"
if [[ $MISSING_EXAMPLE -gt 0 ]]; then
    echo -e "  Missing: ${RED}${MISSING_EXAMPLE}${NC}"
fi
echo -e "${CYAN}============================================${NC}"

if [[ $CREATED -gt 0 ]]; then
    echo ""
    echo -e "${RED}⚠  IMPORTANT: Edit the .env files and replace all CHANGE_ME values!${NC}"
    echo ""
    echo -e "Files to edit:"
    for example in "${!ENV_FILES[@]}"; do
        target="${ENV_FILES[$example]}"
        target_path="$SCRIPT_DIR/$target"
        if [[ -f "$target_path" ]]; then
            count=$(grep -c "CHANGE_ME" "$target_path" 2>/dev/null || echo "0")
            if [[ $count -gt 0 ]]; then
                echo -e "  ${YELLOW}→${NC} $target  (${RED}${count} values to change${NC})"
            fi
        fi
    done
    echo ""
    echo -e "Shared secrets that MUST be identical across services:"
    echo -e "  ${CYAN}JWT_SECRET${NC}     → auth-service, client_service, referal"
    echo -e "  ${CYAN}INTERNAL_API_KEY${NC} → auth-service, client_service, referal"
    echo -e "  ${CYAN}MONGO_APP_PASSWORD${NC} → !gateway/.env ↔ auth-service/.env MONGO_URI"
    echo ""
    echo -e "Generate secrets:  ${GREEN}openssl rand -base64 32${NC}"
    echo -e "Then run:          ${GREEN}./start_all.sh${NC}"
fi
