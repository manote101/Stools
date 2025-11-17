#!/bin/bash
# Script: list_highusage.sh
# Purpose: List users who have consumed 70% or more of their CPU and GPU quotas
# Usage: ./list_highusage.sh [-A] [-u] [-h]

source ~/.bashrc
module load slurm

set -euo pipefail

# Function to show help message
show_help() {
    echo "Usage: $0 [-A] [-u] [-h]"
    echo "  -A    List high usage accounts"
    echo "  -u    List high usage users" 
    echo "  -h    Show this help message"
    echo ""
    echo "If both -A and -u are supplied, lists accounts followed by users"
    echo "If no options are supplied, shows this help message"
    exit 0
}

# Function to extract TRES values from sshare output
extract_tres_value() {
    local tres_string="$1"
    local tres_type="$2"
    
    # Extract the value for specific TRES type (cpu, gpu, etc.)
    echo "$tres_string" | grep -o "${tres_type}=[^,]*" | cut -d= -f2
}

# Function to calculate and display high usage users
list_high_usage_accounts() {
    local threshold=70
    echo "ACCOUNTS with CPU or GPU usage >= ${threshold}%"
    echo "====================================="
    
    # Get all associations with their quotas and usage
    local account_info
    account_info=$(sshare -h -o "Account,GrpTRESMins,GrpTRESRaw" -Pn 2>/dev/null | grep -v '^.*||')
    
    if [ -z "$account_info" ]; then
        echo "Error: Could not retrieve association information" >&2
        return 1
    fi

    # Process each association
    echo "$account_info" | while IFS= read -r line; do
        # Skip lines without user information
        #if echo "$line" | grep -q '^[[:space:]]*$' || ! echo "$line" | awk '{print $2}' | grep -q '[a-zA-Z0-9]'; then
        #    continue
        #fi
        
        local account=$(echo "$line" | awk -F'|' '{gsub(/^[ \t]+/, "", $1); print $1}')
        local quota_tres=$(echo "$line" | awk -F'|' '{print $2}')
        local usage_tres=$(echo "$line" | awk -F'|' '{print $3}')
        
        # Skip if user is empty or contains special values
        if [ -z "$account" ] || [ "$account" = "(null)" ] || [ "$account" = "root" ]; then
            continue
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
        
        # Skip users with zero quotas (no limits set)
        if [ "$cpu_quota" -eq 0 ] || [ "$gpu_quota" -eq 0 ]; then
            continue
        fi
        
        # Calculate percentages
        local cpu_percent=0
        local gpu_percent=0
        
        if [ "$cpu_quota" -gt 0 ]; then
            cpu_percent=$(echo "scale=2; $cpu_used * 100 / $cpu_quota" | bc 2>/dev/null || echo "0")
        fi
        
        if [ "$gpu_quota" -gt 0 ]; then
            gpu_percent=$(echo "scale=2; $gpu_used * 100 / $gpu_quota" | bc 2>/dev/null || echo "0")
        fi
        
        # Compare as integers (bc returns floating point, so we convert to integer for comparison)
        local cpu_percent_int=$(echo "$cpu_percent" | cut -d. -f1)
        local gpu_percent_int=$(echo "$gpu_percent" | cut -d. -f1)
        
        #Check if both CPU and GPU usage are above threshold
        if [ "$cpu_percent_int" -ge "$threshold" ] || [ "$gpu_percent_int" -ge "$threshold" ]; then
            echo "$account,$cpu_percent,$gpu_percent"
        fi
    done
}

# Alternative implementation using sacctmgr for better user discovery
list_high_usage_users() {
    local threshold=70
    echo
    echo "USERS with CPU or GPU usage >= ${threshold}%"
    echo "=================================="
    
    # Get all users from sacctmgr
    local all_users
    all_users=$(sacctmgr show associations format=Account,User -Pn 2>/dev/null | grep -v '^.*|$' | sort -u)
    
    if [ -z "$all_users" ]; then
        echo "Error: Could not retrieve user list" >&2
        return 1
    fi
    
    # Process each user
    echo "$all_users" | while IFS= read -r user_line; do
        local account=$(echo "$user_line" | awk -F'|' '{print $1}')
        local user=$(echo "$user_line" | awk -F'|' '{print $2}')
        
        # Skip empty users or system users
        if [ -z "$user" ] || [ "$user" = "(null)" ] || [ "$user" = "root" ]; then
            continue
        fi
        
        # Get user-specific quota information
        local user_info
        user_info=$(sshare -h -A "$account" -u "$user" -o "Account,User,GrpTRESMins,GrpTRESRaw%120" 2>/dev/null | grep "^ $account.*$user" | head -1)
        
        if [ -z "$user_info" ]; then
            continue
        fi
        
        local quota_tres=$(echo "$user_info" | awk '{print $3}')
        local usage_tres=$(echo "$user_info" | awk '{print $4}')
        
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
        
        # Skip users with zero quotas
        if [ "$cpu_quota" -eq 0 ] || [ "$gpu_quota" -eq 0 ]; then
            continue
        fi
        
        # Calculate percentages
        local cpu_percent=0
        local gpu_percent=0
        
        if [ "$cpu_quota" -gt 0 ]; then
            cpu_percent=$(echo "scale=2; $cpu_used * 100 / $cpu_quota" | bc 2>/dev/null || echo "0")
        fi
        
        if [ "$gpu_quota" -gt 0 ]; then
            gpu_percent=$(echo "scale=2; $gpu_used * 100 / $gpu_quota" | bc 2>/dev/null || echo "0")
        fi
        
        # Compare as integers
        local cpu_percent_int=$(echo "$cpu_percent" | cut -d. -f1)
        local gpu_percent_int=$(echo "$gpu_percent" | cut -d. -f1)
        
        # Check if both CPU and GPU usage are above threshold
        if [ "$cpu_percent_int" -ge "$threshold" ] || [ "$gpu_percent_int" -ge "$threshold" ]; then
            echo "$user,$cpu_percent,$gpu_percent"
        fi
    done
}

# Main execution
echo "Slurm High Usage Users Report"
echo "============================="

# Parse command line options
SHOW_ACCOUNTS=false
SHOW_USERS=false

while getopts "Auh" opt; do
    case $opt in
        A)
            SHOW_ACCOUNTS=true
            ;;
        u)
            SHOW_USERS=true
            ;;
        h)
            show_help
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            show_help
            ;;
    esac
done

# If no options provided, show help
if [ "$SHOW_ACCOUNTS" = false ] && [ "$SHOW_USERS" = false ]; then
    show_help
fi

# Execute based on options
if [ "$SHOW_ACCOUNTS" = true ]; then
    if ! list_high_usage_accounts; then
        echo "Error: Failed to list high usage accounts" >&2
        exit 1
    fi
fi

if [ "$SHOW_USERS" = true ]; then
    if ! list_high_usage_users; then
        echo "Error: Failed to list high usage users" >&2
        exit 1
    fi
fi

echo ""
echo "Report completed."
