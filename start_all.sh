#!/bin/bash
# filepath: c:\Users\d.tolkunov\CodeRepository\GOTOSERVER\start_all.sh
# Script to start all Docker Compose services, starting with gateway (Ubuntu version)

# Base directory where all services are located
BASE_DIR="$(dirname "$(readlink -f "$0")")"
PIDS=()

# Color codes
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

echo -e "${CYAN}=== STARTING GOLDEN HOUSE SERVICES ===${NC}"

# List all folders in the current directory
echo -e "${CYAN}Finding all service directories...${NC}"
ALL_FOLDERS=$(find "$BASE_DIR" -maxdepth 1 -type d -not -path "*/.git" -not -path "$BASE_DIR")
echo -e "${WHITE}Found the following service directories:${NC}"
for folder in $ALL_FOLDERS; do
  echo -e "  - $(basename "$folder")"
done

# Step 1: Start Gateway First
GATEWAY_DIR="$BASE_DIR/!gateway"
if [ -d "$GATEWAY_DIR" ]; then
    echo -e "${GREEN}Starting Gateway first...${NC}"
    
    # Start gateway and wait
    cd "$GATEWAY_DIR" || { echo -e "${RED}Failed to enter Gateway directory${NC}"; exit 1; }
    echo -e "${YELLOW}Executing Docker Compose in Gateway directory...${NC}"
    docker compose up --build -d
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Gateway services started successfully!${NC}"
    else
        echo -e "${RED}Failed to start Gateway. Check errors above.${NC}"
        exit 1
    fi
    
    # Return to base directory
    cd "$BASE_DIR" || { echo -e "${RED}Failed to return to base directory${NC}"; exit 1; }
    
    # Small wait to ensure gateway is ready before other services
    sleep 3
else
    echo -e "${RED}Gateway directory not found: $GATEWAY_DIR${NC}"
    exit 1
fi

update_repository() {
    local repo_path="$1"
    local repo_name="$2"
    
    if [ -d "$repo_path/.git" ]; then
        echo -e "${YELLOW}Updating git repository in $repo_name...${NC}"
        
        # Save current directory
        local current_dir=$(pwd)
        cd "$repo_path" || return 1
        
        # Fetch latest changes
        echo -e "${YELLOW}Running git fetch...${NC}"
        git fetch
        if [ $? -ne 0 ]; then
            echo -e "${RED}Git fetch failed for $repo_name${NC}"
            cd "$current_dir" || return 1
            return 1
        fi
        
        # Pull latest changes
        echo -e "${YELLOW}Running git pull...${NC}"
        git pull
        if [ $? -ne 0 ]; then
            echo -e "${RED}Git pull failed for $repo_name${NC}"
            cd "$current_dir" || return 1
            return 1
        fi
        
        echo -e "${GREEN}Repository $repo_name updated successfully!${NC}"
        cd "$current_dir" || return 1
        return 0
    else
        echo -e "${YELLOW}$repo_name is not a git repository, skipping update${NC}"
        return 0
    fi
}

# Add this code before starting Gateway
echo -e "${YELLOW}Updating Gateway repository...${NC}"
update_repository "$GATEWAY_DIR" "Gateway"

# Step 2: Start all other services in separate terminals
for folder in $ALL_FOLDERS; do
    folder_name=$(basename "$folder")
    
    # Skip the gateway folder since we already handled it
    if [ "$folder_name" == "!gateway" ]; then
        continue
    fi
    if [ "$folder_name" == ".vscode" ]; then
        continue
    fi
    update_repository "$folder" "$folder_name"

    # Check if docker-compose file exists
    if [ ! -f "$folder/docker-compose.yml" ] && [ ! -f "$folder/docker-compose.yaml" ]; then
        echo -e "${YELLOW}No docker-compose file found in $folder_name - skipping${NC}"
        continue
    fi
    
    echo -e "${GREEN}Starting service: $folder_name${NC}"
    
    # Create a script to run in a new terminal
    TMP_SCRIPT=$(mktemp)
    cat > "$TMP_SCRIPT" << EOL
#!/bin/bash
cd "$folder" || exit 1
echo "Starting Docker Compose for $folder_name..."
docker compose up --build -d
if [ \$? -eq 0 ]; then
    echo -e "${GREEN}Docker Compose for $folder_name completed successfully${NC}"
else
    echo -e "${RED}Docker Compose for $folder_name failed!${NC}"
    read -p "Press Enter to exit"
fi
# Remove the temporary script
rm "$TMP_SCRIPT"
EOL
    
    chmod +x "$TMP_SCRIPT"
    
    # Start the process in a terminal and get its PID
    if command -v gnome-terminal &> /dev/null; then
        # For GNOME-based environments (Ubuntu default)
        gnome-terminal -- bash -c "$TMP_SCRIPT; exec bash" &
        PIDS+=($!)
    elif command -v xterm &> /dev/null; then
        # For environments with xterm
        xterm -e "bash $TMP_SCRIPT" &
        PIDS+=($!)
    elif command -v konsole &> /dev/null; then
        # For KDE environments
        konsole -e "bash $TMP_SCRIPT" &
        PIDS+=($!)
    elif command -v terminator &> /dev/null; then
        # Try terminator
        terminator -e "bash $TMP_SCRIPT" &
        PIDS+=($!)
    else
        # Fallback to simple background execution
        echo -e "${YELLOW}No graphical terminal found, running in background${NC}"
        bash "$TMP_SCRIPT" &
        PIDS+=($!)
    fi
    
    # Small pause between starting services
    sleep 1
done

# Step 3: Wait for all processes to exit
echo -e "${CYAN}Waiting for all service terminals to complete...${NC}"
for pid in "${PIDS[@]}"; do
    echo -e "${YELLOW}Waiting for process ID: $pid to complete...${NC}"
    wait "$pid" 2>/dev/null || true
    echo -e "${GREEN}Process ID: $pid has completed.${NC}"
done

echo -e "${GREEN}All Docker Compose commands have completed!${NC}"

# Step 4: Show running containers
echo -e "\n${CYAN}=== RUNNING CONTAINERS ===${NC}"
docker ps -a

echo -e "\n${CYAN}=== ALL SERVICES STARTED ===${NC}"
echo -e "Press Ctrl+C to exit this script"

# Keep the main script running
trap "echo -e \"\n${GREEN}Script terminated.${NC}\"; exit 0" INT
while true; do
    sleep 10
done