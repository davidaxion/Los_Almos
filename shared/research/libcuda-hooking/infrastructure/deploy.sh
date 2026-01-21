#!/bin/bash
#
# deploy.sh - Deploy LittleBoy Research Instance
#
# One-command deployment of GPU research instance with all tools

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$SCRIPT_DIR/terraform"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "${BLUE}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║       LittleBoy Research Instance Deployment                 ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_step() {
    echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

check_requirements() {
    print_step "Checking requirements..."

    # Check Terraform
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform is not installed"
        echo "Install from: https://www.terraform.io/downloads"
        exit 1
    fi
    echo "  ✓ Terraform: $(terraform version -json | jq -r '.terraform_version')"

    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        print_warning "AWS CLI not found (optional but recommended)"
        echo "  Install from: https://aws.amazon.com/cli/"
    else
        echo "  ✓ AWS CLI: $(aws --version | cut -d' ' -f1)"
    fi

    # Check jq
    if ! command -v jq &> /dev/null; then
        print_warning "jq not found (optional)"
    fi
}

setup_ssh_keys() {
    print_step "Setting up SSH keys..."

    SSH_KEY_PATH="$HOME/.ssh/littleboy_research"

    if [ -f "$SSH_KEY_PATH" ]; then
        echo "  ✓ SSH key already exists: $SSH_KEY_PATH"
    else
        echo "  Generating new SSH key..."
        ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_PATH" -N "" -C "littleboy-research"
        echo "  ✓ SSH key generated: $SSH_KEY_PATH"
    fi

    chmod 600 "$SSH_KEY_PATH"
    chmod 644 "${SSH_KEY_PATH}.pub"
}

setup_terraform() {
    print_step "Setting up Terraform configuration..."

    cd "$TF_DIR"

    # Copy terraform.tfvars if it doesn't exist
    if [ ! -f "terraform.tfvars" ]; then
        echo "  Creating terraform.tfvars from example..."
        cp terraform.tfvars.example terraform.tfvars

        # Get user's public IP
        MY_IP=$(curl -s ifconfig.me || echo "0.0.0.0")
        if [ "$MY_IP" != "0.0.0.0" ]; then
            echo "  Detected your IP: $MY_IP"
            sed -i.bak "s|allowed_ssh_cidrs = \[\"0.0.0.0/0\"\]|allowed_ssh_cidrs = [\"$MY_IP/32\"]|" terraform.tfvars
            rm terraform.tfvars.bak 2>/dev/null || true
        fi

        print_warning "terraform.tfvars created - please review and customize if needed"
        echo "  File: $TF_DIR/terraform.tfvars"
    fi

    # Check for default VPC
    if command -v aws &> /dev/null && aws sts get-caller-identity &> /dev/null; then
        echo "  Detecting AWS configuration..."

        REGION=$(grep 'aws_region' terraform.tfvars | cut -d'"' -f2 || echo "us-west-2")
        DEFAULT_VPC=$(aws ec2 describe-vpcs --region "$REGION" --filters "Name=is-default,Values=true" --query 'Vpcs[0].VpcId' --output text 2>/dev/null || echo "")

        if [ -n "$DEFAULT_VPC" ] && [ "$DEFAULT_VPC" != "None" ]; then
            echo "  ✓ Using default VPC: $DEFAULT_VPC"

            # Get default subnet
            DEFAULT_SUBNET=$(aws ec2 describe-subnets --region "$REGION" --filters "Name=vpc-id,Values=$DEFAULT_VPC" "Name=default-for-az,Values=true" --query 'Subnets[0].SubnetId' --output text 2>/dev/null || echo "")

            if [ -n "$DEFAULT_SUBNET" ] && [ "$DEFAULT_SUBNET" != "None" ]; then
                echo "  ✓ Using default subnet: $DEFAULT_SUBNET"

                # Add to terraform.tfvars if not already present
                if ! grep -q "vpc_id" terraform.tfvars; then
                    echo "" >> terraform.tfvars
                    echo "# Auto-detected VPC and Subnet" >> terraform.tfvars
                    echo "vpc_id = \"$DEFAULT_VPC\"" >> terraform.tfvars
                    echo "subnet_id = \"$DEFAULT_SUBNET\"" >> terraform.tfvars
                fi
            fi
        fi
    fi

    # Initialize Terraform
    print_step "Initializing Terraform..."
    terraform init

    echo "  ✓ Terraform initialized"
}

deploy_instance() {
    print_step "Deploying research instance..."

    cd "$TF_DIR"

    # Plan
    echo ""
    echo -e "${YELLOW}Terraform Plan:${NC}"
    terraform plan -out=tfplan

    # Ask for confirmation
    echo ""
    echo -e "${YELLOW}Ready to deploy. This will create AWS resources.${NC}"
    read -p "Continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
        print_warning "Deployment cancelled"
        exit 0
    fi

    # Apply
    terraform apply tfplan
    rm tfplan

    print_step "Instance deployed successfully!"
}

show_connection_info() {
    print_step "Fetching connection information..."

    cd "$TF_DIR"

    INSTANCE_IP=$(terraform output -raw instance_public_ip 2>/dev/null || echo "")
    SSH_COMMAND=$(terraform output -raw ssh_command 2>/dev/null || echo "")

    if [ -z "$INSTANCE_IP" ]; then
        print_error "Failed to get instance IP"
        return
    fi

    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║              Instance Deployed Successfully!                  ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}Instance IP:${NC} $INSTANCE_IP"
    echo -e "${BLUE}SSH Command:${NC} $SSH_COMMAND"
    echo ""
    echo -e "${YELLOW}IMPORTANT:${NC} Setup is still running in the background!"
    echo "  The instance will reboot once setup is complete (~5-10 minutes)"
    echo ""
    echo -e "${BLUE}To monitor setup progress:${NC}"
    echo "  $SSH_COMMAND 'tail -f /var/log/cloud-init-output.log'"
    echo ""
    echo -e "${BLUE}After setup completes, check status:${NC}"
    echo "  $SSH_COMMAND 'cat SETUP_COMPLETE.txt'"
    echo "  $SSH_COMMAND 'gpu-status'"
    echo ""
    echo -e "${BLUE}Quick trace test:${NC}"
    echo "  $SSH_COMMAND 'sudo quick-trace python3 -c \"import torch; print(torch.cuda.is_available())\"'"
    echo ""

    # Save to file
    cat > "$SCRIPT_DIR/CONNECTION_INFO.txt" <<EOF
LittleBoy Research Instance - Connection Info
Generated: $(date)

Instance IP: $INSTANCE_IP
SSH Command: $SSH_COMMAND

Monitor Setup:
  $SSH_COMMAND 'tail -f /var/log/cloud-init-output.log'

Check Status:
  $SSH_COMMAND 'gpu-status'

Quick Test:
  $SSH_COMMAND 'sudo quick-trace python3 -c "import torch; print(torch.cuda.is_available())"'
EOF

    print_step "Connection info saved to: CONNECTION_INFO.txt"
}

upload_code() {
    if [ ! -f "$SCRIPT_DIR/CONNECTION_INFO.txt" ]; then
        print_error "Instance not deployed yet. Run deploy first."
        return
    fi

    print_step "Uploading LittleBoy code to instance..."

    INSTANCE_IP=$(grep "Instance IP:" "$SCRIPT_DIR/CONNECTION_INFO.txt" | cut -d' ' -f3)
    SSH_KEY="$HOME/.ssh/littleboy_research"

    # Wait for instance to be ready
    echo "  Waiting for instance to be ready..."
    for i in {1..30}; do
        if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=5 ubuntu@"$INSTANCE_IP" 'echo ready' &> /dev/null; then
            break
        fi
        sleep 10
        echo -n "."
    done
    echo ""

    # Upload code
    CODE_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

    if [ -d "$CODE_DIR" ]; then
        echo "  Uploading from: $CODE_DIR"

        # Create archive
        TMPFILE=$(mktemp /tmp/littleboy-code.XXXXXX.tar.gz)
        tar czf "$TMPFILE" \
            --exclude='infrastructure/terraform/.terraform' \
            --exclude='infrastructure/terraform/terraform.tfstate*' \
            --exclude='infrastructure/terraform/tfplan' \
            --exclude='*.pyc' \
            --exclude='__pycache__' \
            --exclude='.git' \
            -C "$(dirname "$CODE_DIR")" \
            "$(basename "$CODE_DIR")"

        # Upload
        scp -i "$SSH_KEY" -o StrictHostKeyChecking=no "$TMPFILE" ubuntu@"$INSTANCE_IP":/tmp/littleboy-code.tar.gz

        # Extract on remote
        ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$INSTANCE_IP" \
            'cd ~/littleboy-research && tar xzf /tmp/littleboy-code.tar.gz && rm /tmp/littleboy-code.tar.gz'

        rm "$TMPFILE"

        echo "  ✓ Code uploaded to ~/littleboy-research/"
    else
        print_warning "Code directory not found: $CODE_DIR"
    fi
}

main() {
    print_header

    case "${1:-deploy}" in
        deploy)
            check_requirements
            setup_ssh_keys
            setup_terraform
            deploy_instance
            show_connection_info
            echo ""
            echo -e "${GREEN}Deployment complete!${NC}"
            echo -e "Run: ${BLUE}./deploy.sh upload${NC} to upload your code to the instance"
            ;;

        upload)
            upload_code
            ;;

        destroy)
            print_warning "This will destroy the instance and all data!"
            read -p "Are you sure? (yes/no): " -r
            if [[ $REPLY =~ ^[Yy]es$ ]]; then
                cd "$TF_DIR"
                terraform destroy
                rm -f "$SCRIPT_DIR/CONNECTION_INFO.txt"
                print_step "Instance destroyed"
            fi
            ;;

        ssh)
            if [ -f "$SCRIPT_DIR/CONNECTION_INFO.txt" ]; then
                SSH_CMD=$(grep "SSH Command:" "$SCRIPT_DIR/CONNECTION_INFO.txt" | cut -d' ' -f3-)
                eval "$SSH_CMD"
            else
                print_error "Instance not deployed. Run: ./deploy.sh deploy"
            fi
            ;;

        status)
            if [ -f "$SCRIPT_DIR/CONNECTION_INFO.txt" ]; then
                cat "$SCRIPT_DIR/CONNECTION_INFO.txt"
            else
                print_error "Instance not deployed. Run: ./deploy.sh deploy"
            fi
            ;;

        *)
            echo "Usage: $0 {deploy|upload|destroy|ssh|status}"
            echo ""
            echo "Commands:"
            echo "  deploy  - Deploy new research instance"
            echo "  upload  - Upload LittleBoy code to instance"
            echo "  destroy - Destroy instance"
            echo "  ssh     - Connect to instance"
            echo "  status  - Show connection info"
            exit 1
            ;;
    esac
}

main "$@"
