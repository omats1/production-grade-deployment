#!/bin/bash

###############################################################################
# Production-Grade Dockerized Application Deployment Script
# Author: DevOps Automation
# Description: Automates setup, deployment, and configuration of Dockerized
#              applications on remote Linux servers
###############################################################################

set -euo pipefail  # Exit on error, undefined vars, pipe failures

###############################################################################
# GLOBAL VARIABLES
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy_$(date +%Y%m%d_%H%M%S).log"
TEMP_DIR="${SCRIPT_DIR}/.tmp_deploy"

# User Input Variables
GIT_REPO=""
GIT_PAT=""
GIT_BRANCH="main"
SSH_USER=""
SSH_IP=""
SSH_KEY=""
APP_PORT=""
PROJECT_NAME=""
CLEANUP_MODE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

###############################################################################
# LOGGING AND OUTPUT FUNCTIONS
###############################################################################

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"
}

print_header() {
    echo ""
    echo "============================================================" | tee -a "$LOG_FILE"
    echo "  $*" | tee -a "$LOG_FILE"
    echo "============================================================" | tee -a "$LOG_FILE"
}

###############################################################################
# ERROR HANDLING
###############################################################################

cleanup_on_error() {
    local exit_code=$?
    log_error "Script failed at line $1 with exit code ${exit_code}"
    log_error "Check ${LOG_FILE} for details"
    exit "${exit_code}"
}

trap 'cleanup_on_error ${LINENO}' ERR

###############################################################################
# VALIDATION FUNCTIONS
###############################################################################

validate_url() {
    local url="$1"
    if [[ ! "$url" =~ ^https?:// ]]; then
        return 1
    fi
    return 0
}

validate_ip() {
    local ip="$1"
    if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 0
    fi
    return 1
}

validate_port() {
    local port="$1"
    if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
        return 0
    fi
    return 1
}

validate_ssh_key() {
    local key_path="$1"
    if [ ! -f "$key_path" ]; then
        log_error "SSH key not found at: $key_path"
        return 1
    fi
    
    # Check permissions
    local perms=$(stat -c %a "$key_path" 2>/dev/null || stat -f %A "$key_path" 2>/dev/null)
    if [ "$perms" != "600" ] && [ "$perms" != "400" ]; then
        log_warning "SSH key permissions are $perms, setting to 600"
        chmod 600 "$key_path"
    fi
    return 0
}

###############################################################################
# STEP 1: COLLECT AND VALIDATE USER INPUT
###############################################################################

collect_user_input() {
    print_header "STEP 1: Collecting Deployment Parameters"
    
    # Git Repository URL
    while true; do
        read -p "Enter Git Repository URL (https://...): " GIT_REPO
        if validate_url "$GIT_REPO"; then
            log_success "Valid repository URL provided"
            break
        fi
        log_error "Invalid URL format. Must start with http:// or https://"
    done
    
    # Personal Access Token
    while true; do
        read -sp "Enter Personal Access Token (PAT): " GIT_PAT
        echo ""
        if [ -n "$GIT_PAT" ]; then
            log_success "PAT received (hidden from logs)"
            break
        fi
        log_error "PAT cannot be empty"
    done
    
    # Branch name
    read -p "Enter branch name (default: main): " GIT_BRANCH
    GIT_BRANCH=${GIT_BRANCH:-main}
    log_info "Using branch: $GIT_BRANCH"
    
    # SSH Username
    while true; do
        read -p "Enter SSH username: " SSH_USER
        if [ -n "$SSH_USER" ]; then
            log_success "SSH username: $SSH_USER"
            break
        fi
        log_error "Username cannot be empty"
    done
    
    # SSH Server IP
    while true; do
        read -p "Enter server IP address: " SSH_IP
        if validate_ip "$SSH_IP"; then
            log_success "Valid IP address: $SSH_IP"
            break
        fi
        log_error "Invalid IP address format"
    done
    
    # SSH Key Path
    while true; do
        read -p "Enter SSH key path: " SSH_KEY
        SSH_KEY="${SSH_KEY/#\~/$HOME}"  # Expand tilde
        if validate_ssh_key "$SSH_KEY"; then
            log_success "SSH key validated: $SSH_KEY"
            break
        fi
    done
    
    # Application Port
    while true; do
        read -p "Enter application port (1-65535): " APP_PORT
        if validate_port "$APP_PORT"; then
            log_success "Application port: $APP_PORT"
            break
        fi
        log_error "Invalid port number"
    done
    
    # Extract project name from repo URL
    PROJECT_NAME=$(basename "$GIT_REPO" .git)
    log_info "Project name: $PROJECT_NAME"
    
    echo ""
    log_info "Configuration Summary:"
    log_info "  Repository: $GIT_REPO"
    log_info "  Branch: $GIT_BRANCH"
    log_info "  Server: $SSH_USER@$SSH_IP"
    log_info "  Port: $APP_PORT"
    echo ""
    
    read -p "Proceed with deployment? (yes/no): " confirm
    if [[ ! "$confirm" =~ ^[Yy][Ee]?[Ss]?$ ]]; then
        log_warning "Deployment cancelled by user"
        exit 0
    fi
}

###############################################################################
# STEP 2: CLONE OR UPDATE REPOSITORY
###############################################################################

clone_repository() {
    print_header "STEP 2: Cloning/Updating Repository"
    
    # Create temp directory
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR"
    
    # Construct authenticated URL
    local auth_url=$(echo "$GIT_REPO" | sed "s|https://|https://${GIT_PAT}@|")
    
    if [ -d "$PROJECT_NAME" ]; then
        log_info "Repository already exists, pulling latest changes..."
        cd "$PROJECT_NAME"
        
        git fetch origin "$GIT_BRANCH" 2>&1 | tee -a "$LOG_FILE"
        git checkout "$GIT_BRANCH" 2>&1 | tee -a "$LOG_FILE"
        git pull origin "$GIT_BRANCH" 2>&1 | tee -a "$LOG_FILE"
        
        log_success "Repository updated successfully"
    else
        log_info "Cloning repository..."
        git clone -b "$GIT_BRANCH" "$auth_url" "$PROJECT_NAME" 2>&1 | grep -v "$GIT_PAT" | tee -a "$LOG_FILE"
        cd "$PROJECT_NAME"
        log_success "Repository cloned successfully"
    fi
    
    # Show current commit
    local commit=$(git rev-parse --short HEAD)
    log_info "Current commit: $commit"
}

###############################################################################
# STEP 3: VERIFY DOCKER CONFIGURATION
###############################################################################

verify_docker_config() {
    print_header "STEP 3: Verifying Docker Configuration"
    
    if [ -f "Dockerfile" ]; then
        log_success "Dockerfile found"
    elif [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ]; then
        log_success "docker-compose.yml found"
    else
        log_error "Neither Dockerfile nor docker-compose.yml found!"
        exit 1
    fi
    
    log_info "Project structure verified"
}

###############################################################################
# STEP 4: TEST SSH CONNECTIVITY
###############################################################################

test_ssh_connectivity() {
    print_header "STEP 4: Testing SSH Connectivity"
    
    log_info "Testing SSH connection to $SSH_USER@$SSH_IP..."
    
    if ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$SSH_USER@$SSH_IP" "exit" 2>&1 | tee -a "$LOG_FILE"; then
        log_success "SSH connection successful"
    else
        log_error "SSH connection failed"
        exit 1
    fi
    
    # Test sudo access
    log_info "Verifying sudo access..."
    if ssh -i "$SSH_KEY" "$SSH_USER@$SSH_IP" "sudo -n true" 2>/dev/null; then
        log_success "Passwordless sudo confirmed"
    else
        log_warning "User may need sudo password. Ensure passwordless sudo is configured."
    fi
}

###############################################################################
# STEP 5: PREPARE REMOTE ENVIRONMENT
###############################################################################

prepare_remote_environment() {
    print_header "STEP 5: Preparing Remote Environment"
    
    log_info "Installing required packages on remote server..."
    
    ssh -i "$SSH_KEY" "$SSH_USER@$SSH_IP" bash << 'ENDSSH' 2>&1 | tee -a "$LOG_FILE"
        set -e
        
        echo "[INFO] Updating package lists..."
        sudo apt-get update -qq
        
        echo "[INFO] Installing prerequisites..."
        sudo apt-get install -y -qq apt-transport-https ca-certificates curl software-properties-common gnupg nginx
        
        # Install Docker if not present
        if ! command -v docker &> /dev/null; then
            echo "[INFO] Installing Docker..."
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            sudo apt-get update -qq
            sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io
            echo "[SUCCESS] Docker installed"
        else
            echo "[INFO] Docker already installed"
        fi
        
        # Install Docker Compose if not present
        if ! command -v docker-compose &> /dev/null; then
            echo "[INFO] Installing Docker Compose..."
            sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
            sudo chmod +x /usr/local/bin/docker-compose
            echo "[SUCCESS] Docker Compose installed"
        else
            echo "[INFO] Docker Compose already installed"
        fi
        
        # Add user to docker group
        if ! groups $USER | grep -q docker; then
            echo "[INFO] Adding user to docker group..."
            sudo usermod -aG docker $USER
            echo "[WARNING] User added to docker group. May need to logout/login."
        fi
        
        # Start and enable services
        echo "[INFO] Enabling services..."
        sudo systemctl enable docker
        sudo systemctl start docker
        sudo systemctl enable nginx
        sudo systemctl start nginx
        
        # Display versions
        echo ""
        echo "[INFO] Installed versions:"
        docker --version
        docker-compose --version
        nginx -v
ENDSSH
    
    log_success "Remote environment prepared"
}

###############################################################################
# STEP 6: DEPLOY DOCKERIZED APPLICATION
###############################################################################

deploy_application() {
    print_header "STEP 6: Deploying Dockerized Application"

    local remote_path="/home/$SSH_USER/deployments/$PROJECT_NAME"

    log_info "Creating deployment directory on remote server..."
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$SSH_IP" "mkdir -p $remote_path"

    log_info "Transferring project files..."

    # Try rsync, fallback to tar+scp if rsync fails (Windows compatibility)
    if rsync -avz --delete -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no" \
        --exclude '.git' \
        --exclude 'node_modules' \
        --exclude '__pycache__' \
        --exclude '.env' \
        "${TEMP_DIR}/${PROJECT_NAME}/" \
        "${SSH_USER}@${SSH_IP}:${remote_path}/" 2>&1 | tee -a "$LOG_FILE"; then
        log_success "Files transferred successfully via rsync"
    else
        log_warning "rsync failed, falling back to tar+scp method..."

        # Create temporary archive
        local temp_archive="/tmp/deploy_${PROJECT_NAME}_$(date +%s).tar.gz"

        cd "${TEMP_DIR}"
        tar czf "$temp_archive" \
            --exclude='.git' \
            --exclude='node_modules' \
            --exclude='__pycache__' \
            --exclude='.env' \
            "${PROJECT_NAME}/" 2>&1 | tee -a "$LOG_FILE"

        log_info "Transferring via scp..."
        scp -i "$SSH_KEY" -o StrictHostKeyChecking=no "$temp_archive" "${SSH_USER}@${SSH_IP}:/tmp/" 2>&1 | tee -a "$LOG_FILE"

        log_info "Extracting on remote server..."
        ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$SSH_IP" \
            "mkdir -p ${remote_path} && cd ${remote_path} && tar xzf /tmp/$(basename $temp_archive) --strip-components=1 && rm /tmp/$(basename $temp_archive)" 2>&1 | tee -a "$LOG_FILE"

        rm -f "$temp_archive"
        log_success "Files transferred successfully via tar+scp"
    fi

    log_info "Building and starting Docker container..."

    # Note: No single quotes around ENDSSH so that variables expand properly
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$SSH_IP" bash << ENDSSH 2>&1 | tee -a "$LOG_FILE"
set -e
cd $remote_path

# Convert project name to lowercase for Docker compliance
LOWER_NAME=\$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]')

echo "[INFO] Stopping and removing existing containers..."
docker stop \${LOWER_NAME}_app 2>/dev/null || true
docker rm \${LOWER_NAME}_app 2>/dev/null || true
docker rmi \${LOWER_NAME}:latest 2>/dev/null || true

# Build new image
if [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ]; then
    echo "[INFO] Using docker-compose..."
    docker-compose down 2>/dev/null || true
    docker-compose up -d --build
else
    echo "[INFO] Using Dockerfile..."
    docker build -t "\${LOWER_NAME}:latest" .

    echo "[INFO] Running new container..."
    docker run -d \
        --name \${LOWER_NAME}_app \
        -p \${APP_PORT}:\${APP_PORT} \
        --restart unless-stopped \
        \${LOWER_NAME}:latest
fi

echo "[INFO] Waiting for container to start..."
sleep 5

if docker ps | grep -q \${LOWER_NAME}_app; then
    echo "[SUCCESS] Container is running:"
    docker ps | grep \${LOWER_NAME}_app
else
    echo "[ERROR] Container failed to start"
    docker logs \${LOWER_NAME}_app || docker-compose logs
    exit 1
fi
ENDSSH

    log_success "Application deployed successfully"
}


###############################################################################
# STEP 7: CONFIGURE NGINX REVERSE PROXY
###############################################################################

configure_nginx() {
    print_header "STEP 7: Configuring Nginx Reverse Proxy"
    
    log_info "Creating Nginx configuration..."
    
    ssh -i "$SSH_KEY" "$SSH_USER@$SSH_IP" bash << ENDSSH 2>&1 | tee -a "$LOG_FILE"
        set -e
        
        # Create Nginx config
        sudo tee /etc/nginx/sites-available/${PROJECT_NAME} > /dev/null << 'EOF'
server {
    listen 80;
    server_name _;
    
    client_max_body_size 100M;
    
    location / {
        proxy_pass http://localhost:${APP_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_read_timeout 300s;
        proxy_connect_timeout 75s;
    }
}
EOF
        
        # Enable site
        sudo ln -sf /etc/nginx/sites-available/${PROJECT_NAME} /etc/nginx/sites-enabled/${PROJECT_NAME}
        
        # Remove default if exists
        sudo rm -f /etc/nginx/sites-enabled/default
        
        # Test configuration
        echo "[INFO] Testing Nginx configuration..."
        sudo nginx -t
        
        # Reload Nginx
        echo "[INFO] Reloading Nginx..."
        sudo systemctl reload nginx
        
        echo "[SUCCESS] Nginx configured and reloaded"
ENDSSH
    
    log_success "Nginx reverse proxy configured"
}

###############################################################################
# STEP 8: VALIDATE DEPLOYMENT
###############################################################################

validate_deployment() {
    print_header "STEP 8: Validating Deployment"
    
    log_info "Running deployment validation checks..."
    
    # Check Docker service
    log_info "Checking Docker service..."
    if ssh -i "$SSH_KEY" "$SSH_USER@$SSH_IP" "systemctl is-active docker" &>/dev/null; then
        log_success "Docker service is active"
    else
        log_error "Docker service is not running"
        return 1
    fi
    
    # Check container health
    log_info "Checking container health..."
    if ssh -i "$SSH_KEY" "$SSH_USER@$SSH_IP" "docker ps | grep -q $PROJECT_NAME"; then
        log_success "Container is running"
    else
        log_error "Container is not running"
        return 1
    fi
    
    # Check Nginx
    log_info "Checking Nginx service..."
    if ssh -i "$SSH_KEY" "$SSH_USER@$SSH_IP" "systemctl is-active nginx" &>/dev/null; then
        log_success "Nginx service is active"
    else
        log_error "Nginx service is not running"
        return 1
    fi
    
    # Test application endpoint
    log_info "Testing application endpoint..."
    sleep 3  # Give app time to fully start
    
    if ssh -i "$SSH_KEY" "$SSH_USER@$SSH_IP" "curl -f -s -o /dev/null -w '%{http_code}' http://localhost:$APP_PORT" &>/dev/null; then
        log_success "Application responding on port $APP_PORT"
    else
        log_warning "Application may not be responding yet on port $APP_PORT"
    fi
    
    # Test Nginx proxy
    log_info "Testing Nginx reverse proxy..."
    if ssh -i "$SSH_KEY" "$SSH_USER@$SSH_IP" "curl -f -s -o /dev/null http://localhost" &>/dev/null; then
        log_success "Nginx proxy is working"
    else
        log_warning "Nginx proxy test inconclusive"
    fi
    
    log_success "Validation complete"
}

###############################################################################
# CLEANUP FUNCTION
###############################################################################

perform_cleanup() {
    print_header "CLEANUP MODE: Removing Deployed Resources"
    
    log_warning "This will remove all deployed resources for $PROJECT_NAME"
    read -p "Are you sure? (yes/no): " confirm
    if [[ ! "$confirm" =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Cleanup cancelled"
        exit 0
    fi
    
    log_info "Removing resources on remote server..."
    
    ssh -i "$SSH_KEY" "$SSH_USER@$SSH_IP" bash << ENDSSH 2>&1 | tee -a "$LOG_FILE"
        set -e
        
        # Stop and remove containers
        echo "[INFO] Stopping containers..."
        docker stop ${PROJECT_NAME}_app 2>/dev/null || true
        docker rm ${PROJECT_NAME}_app 2>/dev/null || true
        docker-compose -f /home/$SSH_USER/deployments/${PROJECT_NAME}/docker-compose.yml down 2>/dev/null || true
        
        # Remove images
        echo "[INFO] Removing images..."
        docker rmi ${PROJECT_NAME}:latest 2>/dev/null || true
        
        # Remove deployment directory
        echo "[INFO] Removing deployment directory..."
        rm -rf /home/$SSH_USER/deployments/${PROJECT_NAME}
        
        # Remove Nginx config
        echo "[INFO] Removing Nginx configuration..."
        sudo rm -f /etc/nginx/sites-enabled/${PROJECT_NAME}
        sudo rm -f /etc/nginx/sites-available/${PROJECT_NAME}
        sudo nginx -t && sudo systemctl reload nginx
        
        echo "[SUCCESS] Cleanup complete"
ENDSSH
    
    log_success "All resources removed successfully"
}

###############################################################################
# MAIN FUNCTION
###############################################################################

main() {
    # Print banner
    echo "============================================================"
    echo "  Production Deployment Automation Script"
    echo "  Version: 1.0.0"
    echo "============================================================"
    echo ""
    
    log_info "Starting deployment process..."
    log_info "Log file: $LOG_FILE"
    echo ""
    
    # Check for cleanup flag
    if [ "${1:-}" = "--cleanup" ]; then
        CLEANUP_MODE=true
        collect_user_input
        perform_cleanup
        exit 0
    fi
    
    # Normal deployment flow
    collect_user_input
    clone_repository
    verify_docker_config
    test_ssh_connectivity
    prepare_remote_environment
    deploy_application
    configure_nginx
    validate_deployment
    
    # Print success summary
    print_header "DEPLOYMENT SUCCESSFUL!"
    echo ""
    log_success "Application deployed successfully!"
    log_info "Access your application at: http://$SSH_IP"
    log_info "Container port: $APP_PORT"
    log_info "Project: $PROJECT_NAME"
    echo ""
    log_info "Useful commands:"
    log_info "  View logs: ssh -i $SSH_KEY $SSH_USER@$SSH_IP 'docker logs ${PROJECT_NAME}_app'"
    log_info "  Restart: ssh -i $SSH_KEY $SSH_USER@$SSH_IP 'docker restart ${PROJECT_NAME}_app'"
    log_info "  Cleanup: ./deploy.sh --cleanup"
    echo ""
    log_info "Deployment log saved to: $LOG_FILE"
    echo "============================================================"
}

# Run main function
main "$@"
