#!/bin/bash
# Script: list_slurm_quotas.sh
# Purpose: List CPU and GPU quotas for Slurm accounts or users
# Usage:
#   List account: ./show_quota.sh -A <account-name>
#   List user:    ./show_quota.sh -A <account-name> -u <user-name>

# source ~/.basrc
# module load slurm

set -euo pipefail

# Initialize variables
account_name=""
user_name=""

# Function to display usage
show_usage() {
    echo "Usage: $0 -A <account-name> [-u <user-name>]"
    echo "Options:"
    echo "  -A <account-name>  Specify the account name (required)"
    echo "  -u <user-name>     Specify the user name (optional, for user-specific quotas)"
    echo ""
    echo "Examples:"
    echo "  List account quotas: $0 -A ai-lab"
    echo "  List user quotas:    $0 -A ai-lab -u john.doe"
    exit 1
}

# Parse command line arguments
while getopts "A:u:h" opt; do
    case $opt in
        A)
            account_name="$OPTARG"
            ;;
        u)
            user_name="$OPTARG"
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

# Function to extract TRES values from sshare output
extract_tres_value() {
    local tres_string="$1"
    local tres_type="$2"
    
    # Extract the value for specific TRES type (cpu, gpu, etc.)
    echo "$tres_string" | grep -o "${tres_type}=[^,]*" | cut -d= -f2
}

# Function to display quotas in table format
display_quotas() {
    local acct="$1"
    local user="${2:-}"
    local quota_info
    local usage_info
    
    if [ -z "$user" ]; then
        # Get account quota and usage information
        echo "Fetching ACCOUNT quotas for: $acct"
        echo "====================================="
        
        quota_info=$(sshare -h -A "$acct" -o Account,GrpTRESMins 2>/dev/null | grep "^$acct" | head -1)
        usage_info=$(sshare -h -A "$acct" -o "Account,GrpTRESRaw%120" 2>/dev/null | grep "^$acct" | head -1)
    else
        # Get user quota and usage information
        echo "Fetching USER quotas for: $user in account: $acct"
        echo "=================================================="
        
        quota_info=$(sshare -h -A "$acct" -u "$user" -o Account,User,GrpTRESMins 2>/dev/null | grep "^ $acct.*$user" | head -1)
        usage_info=$(sshare -h -A "$acct" -u "$user" -o "Account,User,GrpTRESRaw%120" 2>/dev/null | grep "^ $acct.*$user" | head -1)
    fi
    
    if [ -z "$quota_info" ]; then
        echo "Error: Could not retrieve quota information" >&2
        return 1
    fi
    
    # Extract TRES fields
    if [ -z "$user" ]; then
        local quota_tres=$(echo "$quota_info" | awk '{print $2}')
        local usage_tres=$(echo "$usage_info" | awk '{print $2}')
    else
        local quota_tres=$(echo "$quota_info" | awk '{print $3}')
        local usage_tres=$(echo "$usage_info" | awk '{print $3}')
    fi
    
    # Extract CPU and GPU values
    local cpu_quota=$(extract_tres_value "$quota_tres" "cpu")
    local gpu_quota=$(extract_tres_value "$quota_tres" "gpu")
    
    local cpu_used=$(extract_tres_value "$usage_tres" "cpu")
    local gpu_used=$(extract_tres_value "$usage_tres" "gpu")
    
    # Set default values if empty
    cpu_quota=${cpu_quota:-0}
    gpu_quota=${gpu_quota:-0}
    cpu_used=${cpu_used:-0}
    gpu_used=${gpu_used:-0}
    
    # Calculate available and percentages
    local cpu_available=$((cpu_quota - cpu_used))
    local gpu_available=$((gpu_quota - gpu_used))
    
    local cpu_percent=0
    local gpu_percent=0
    
    if [ "$cpu_quota" -gt 0 ]; then
        cpu_percent=$(echo "scale=2; $cpu_used * 100 / $cpu_quota" | bc 2>/dev/null || echo "0.00")
    fi
    
    if [ "$gpu_quota" -gt 0 ]; then
        gpu_percent=$(echo "scale=2; $gpu_used * 100 / $gpu_quota" | bc 2>/dev/null || echo "0.00")
    fi
    
    # Display the table
    echo
    printf "             |    CPU    |  GPU     \n"
    printf "+------------+-----------+----------+\n"
    printf "| Quota      | %9s | %8s |\n" "$cpu_quota" "$gpu_quota"
    printf "| Used       | %9s | %8s |\n" "$cpu_used" "$gpu_used"
    printf "| Available  | %9s | %8s |\n" "$cpu_available" "$gpu_available"
    printf "| Percentage | %8s%% | %7s%% |\n" "$cpu_percent" "$gpu_percent"
    printf "+------------+-----------+----------+\n"
    
    # Display additional information
    echo
    echo "Additional Information:"
    echo "-----------------------"
    if [ -z "$user" ]; then
        echo "Type: Account-wide quotas"
        # List users in the account
        local users
        # users=$(sacctmgr show associations where account="$acct" format=User -Pn 2>/dev/null | sort -u | grep -v '^$')
        users=$(sacctmgr show associations where account="$acct" format=User -Pn 2>/dev/null | grep -v '^$' | sort -u)
        if [ -n "$users" ]; then
            echo "Users in account: $(echo "$users" | wc -l)"
            echo "$users" | head -5 | while IFS= read -r u; do
                echo "  - $u"
            done
            if [ $(echo "$users" | wc -l) -gt 5 ]; then
                echo "  ... and more"
            fi
        fi
    else
        echo "Type: User-specific quotas"
        echo "Account: $acct"
        echo "User: $user"
    fi
}

# Main execution
echo "Slurm Quota Information Tool"
echo "============================"

# Check if account exists
if ! sshare -h -A "$account_name" -o Account 2>/dev/null | grep -q "^$account_name"; then
    echo "Error: Account '$account_name' not found." >&2
    exit 1
fi

# Check if user exists (if specified)
if [ -n "$user_name" ]; then
    if ! sshare -h -A "$account_name" -u "$user_name" -o Account,User 2>/dev/null | grep -q "^ $account_name.*$user_name"; then
        echo "Error: User '$user_name' not found in account '$account_name'." >&2
        exit 1
    fi
fi

# Display the quotas
display_quotas "$account_name" "$user_name"

echo
