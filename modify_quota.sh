#!/bin/bash
# Script: add_slurm_resources.sh
# Purpose: Add CPU and GPU resources to Slurm accounts or users
# Usage:
#   Add to account: ./modify_quota.sh -A <account-name> -c <num-cpu> -g <num-gpu>
#   Add to user:    ./modify_quota.sh -A <account-name> -u <user-name> -c <num-cpu> -g <num-gpu>

source ~/.bashrc
module load slurm

set -euo pipefail

# Initialize variables
account_name=""
user_name=""
add_cpu=0
add_gpu=0

# Function to display usage
show_usage() {
    echo "Usage: $0 -A <account-name> [-u <user-name>] -c <num-cpu> -g <num-gpu>"
    echo "Options:"
    echo "  -A <account-name>  Specify the account name (required)"
    echo "  -u <user-name>     Specify the user name (optional, for user-specific limits)"
    echo "  -c <num-cpu>       Number of CPU minutes to add (required, must be positive integer)"
    echo "  -g <num-gpu>       Number of GPU minutes to add (required, must be positive integer)"
    echo ""
    echo "Examples:"
    echo "  Add to account: $0 -A ai-lab -c 100000 -g 5000"
    echo "  Add to user:    $0 -A ai-lab -u john.doe -c 50000 -g 2000"
    echo
    exit 1
}

# Function to validate integer
validate_integer() {
    local value="$1"
    local name="$2"
    
    # Check if it's a positive integer
    if [[ ! "$value" =~ ^[0-9]+$ ]]; then
        echo "Error: $name must be a positive integer. Got: '$value'" >&2
        return 1
    fi
    
    # Check if it's greater than 0
    if [ "$value" -le 0 ]; then
        echo "Error: $name must be greater than 0. Got: '$value'" >&2
        return 1
    fi
    
    return 0
}

# Parse command line arguments
while getopts "A:u:c:g:h" opt; do
    case $opt in
        A)
            account_name="$OPTARG"
            ;;
        u)
            user_name="$OPTARG"
            ;;
        c)
            add_cpu="$OPTARG"
            ;;
        g)
            add_gpu="$OPTARG"
            ;;
        h)
            show_usage
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            show_usage
            ;;
        :)
            echo "Option -$OPTARG requires an argument." >&2
            show_usage
            ;;
    esac
done

# Validate required parameters
if [ -z "$account_name" ]; then
    echo "Error: Account name (-A) is required." >&2
    show_usage
fi

# Validate CPU and GPU are positive integers
if ! validate_integer "$add_cpu" "CPU minutes"; then
    show_usage
fi

if ! validate_integer "$add_gpu" "GPU minutes"; then
    show_usage
fi

# Function to extract TRES values from sshare output
extract_tres_value() {
    local tres_string="$1"
    local tres_type="$2"
    
    # Extract the value for specific TRES type (cpu, gpu, etc.)
    echo "$tres_string" | grep -o "${tres_type}=[^,]*" | cut -d= -f2
}

# Function to get current TRES values
get_current_tres() {
    local acct="$1"
    local user="${2:-}"
    
    local query_info
    if [ -z "$user" ]; then
        # Get account information
        query_info=$(sshare -ah -A "$acct" -o Account,GrpTRESMins 2>/dev/null | grep "^$acct" | head -1)
    else
        # Get user information
        query_info=$(sshare -h -A "$acct" -u "$user" -o Account,User,GrpTRESMins 2>/dev/null | grep "^ $acct.*$user" | head -1)
    fi
    
    if [ -z "$query_info" ]; then
        echo "Error: Could not retrieve current TRES information" >&2
        return 1
    fi
    
    # Extract TRES field (field 2 for account, field 3 for user)
    if [ -z "$user" ]; then
        echo "$query_info" | awk '{print $2}'
    else
        echo "$query_info" | awk '{print $3}'
    fi
}

# Function to calculate new TRES string
calculate_new_tres() {
    local current_tres="$1"
    local add_cpu="$2"
    local add_gpu="$3"
    
    # Extract current values
    local current_cpu=$(extract_tres_value "$current_tres" "cpu")
    local current_gpu=$(extract_tres_value "$current_tres" "gpu")
    
    # Set defaults if empty
    current_cpu=${current_cpu:-0}
    current_gpu=${current_gpu:-0}
    
    # Calculate new values
    local new_cpu=$((current_cpu + add_cpu))
    local new_gpu=$((current_gpu + add_gpu))
    
    # Build new TRES string
    local new_tres="cpu=$new_cpu,gres/gpu=$new_gpu"
    
    # Preserve other TRES types if they exist
    if echo "$current_tres" | grep -q "billing="; then
        local billing=$(extract_tres_value "$current_tres" "billing")
        new_tres="$new_tres,billing=$billing"
    fi
    
    if echo "$current_tres" | grep -q "memory="; then
        local memory=$(extract_tres_value "$current_tres" "memory")
        new_tres="$new_tres,memory=$memory"
    fi
    
    if echo "$current_tres" | grep -q "node="; then
        local node=$(extract_tres_value "$current_tres" "node")
        new_tres="$new_tres,node=$node"
    fi
    
    echo "$new_tres"
}

# Function to update TRES limits
update_tres_limits() {
    local acct="$1"
    local user="${2:-}"
    local new_tres="$3"
    
    local sacctmgr_cmd
    if [ -z "$user" ]; then
        # Update account limits
        sacctmgr_cmd="sacctmgr modify account where account=$acct set GrpTRESMins=$new_tres -i"
        echo "Updating account limits: $sacctmgr_cmd"
    else
        # Update user limits
        sacctmgr_cmd="sacctmgr modify user where account=$acct and user=$user set GrpTRESMins=$new_tres -i"
        echo "Updating user limits: $sacctmgr_cmd"
    fi
    
    # Execute the command
    if eval "$sacctmgr_cmd"; then
        echo "✓ Successfully updated limits"
        return 0
    else
        echo "✗ Failed to update limits" >&2
        return 1
    fi
}

# Main execution
echo "Slurm Resource Addition Tool"
echo "============================"

# Check if account exists
if ! sshare -A "$account_name" -o Account 2>/dev/null | grep -q "^$account_name"; then
    echo "Error: Account '$account_name' not found." >&2
    exit 1
fi

# Check if user exists (if specified)
if [ -n "$user_name" ]; then
    if ! sshare -A "$account_name" -u "$user_name" -o Account,User 2>/dev/null | grep -q "^ $account_name.*$user_name"; then
        echo "Error: User '$user_name' not found in account '$account_name'." >&2
        exit 1
    fi
    echo "Target: User '$user_name' in account '$account_name'"
else
    echo "Target: Account '$account_name'"
fi

echo "Resources to add: CPU=$add_cpu minutes, GPU=$add_gpu minutes"
echo

# Get current TRES values
current_tres=$(get_current_tres "$account_name" "$user_name")

if [ -z "$current_tres" ] || [ "$current_tres" = "(null)" ]; then
    current_tres="cpu=0,gpu=0"
    echo "No existing limits found, starting from zero"
else
    echo "Current TRES: $current_tres"
fi

# Calculate new TRES values
echo
echo "Calculating new limits..."
new_tres=$(calculate_new_tres "$current_tres" "$add_cpu" "$add_gpu")
echo "New TRES: $new_tres"

# Extract and display current and new values for verification
current_cpu=$(extract_tres_value "$current_tres" "cpu")
current_gpu=$(extract_tres_value "$current_tres" "gpu")
new_cpu=$(extract_tres_value "$new_tres" "cpu")
new_gpu=$(extract_tres_value "$new_tres" "gpu")

current_cpu=${current_cpu:-0}
current_gpu=${current_gpu:-0}

echo
echo "Summary of changes:"
printf "+-----------------+-----------+-----------+------------+\n"
printf "| Resource        | Current   | Added     | New Total  |\n"
printf "+-----------------+-----------+-----------+------------+\n"
printf "| CPU Minutes     | %9s | %9s | %10s |\n" "$current_cpu" "$add_cpu" "$new_cpu"
printf "| GPU Minutes     | %9s | %9s | %10s |\n" "$current_gpu" "$add_gpu" "$new_gpu"
printf "+-----------------+-----------+-----------+------------+\n"

# Ask for confirmation
echo
read -p "Do you want to apply these changes? (yes/no): " confirmation
if [[ ! "$confirmation" =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Operation cancelled."
    exit 0
fi

echo
echo "Applying changes..."

# Update the limits
if update_tres_limits "$account_name" "$user_name" "$new_tres"; then
    echo
    echo "✓ Successfully updated resources!"
    echo "✓ New limits applied:"
    echo "  - CPU: $new_cpu minutes"
    echo "  - GPU: $new_gpu minutes"
else
    echo
    echo "✗ Failed to update resources. Please check your permissions and try again." >&2
    exit 1
fi

echo
echo "Done."
