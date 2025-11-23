import sys

def parse_tres_field(field):
    """Parse a TRES string like 'cpu=650,mem=1200,gres/gpu=115'."""
    data = {}
    if not field:
        return data
    items = field.split(',')
    for item in items:
        if '=' in item:
            k, v = item.split('=')
            data[k.strip()] = int(v.strip())
    return data


def process_file(tres_percent, filename):
    with open(filename, "r") as f:
        for line in f:
            raw = line.rstrip("\n")
            stripped = raw.lstrip()
            leading_spaces = len(raw) - len(stripped)

            # Split octets
            parts = stripped.split("|")

            # Skip non-data lines
            if len(parts) < 3:
                continue

            # --- 1. ROOT row (0 leading spaces + value == "root") ---
            if leading_spaces == 0 and parts[0] == "root":
                continue

            # --- 2. ACCOUNT record (1 leading space) ---
            if leading_spaces == 1:
                account = parts[0].strip()
                quota_field = parts[2]
                usage_field = parts[3] if len(parts) > 3 else ""
                record_type = "ACCOUNT"

            # --- 3. USER record (2 leading spaces) ---
            elif leading_spaces == 2:
                account = parts[0].strip()
                user = parts[1].strip()
                quota_field = parts[2]
                usage_field = parts[3] if len(parts) > 3 else ""
                record_type = "USER"

            else:
                continue

            # Extract quotas and usage
            quota = parse_tres_field(quota_field)
            usage = parse_tres_field(usage_field)

            cpu_quota = quota.get("cpu", 0)
            gpu_quota = quota.get("gres/gpu", 0)

            cpu_usage = usage.get("cpu", 0)
            gpu_usage = usage.get("gres/gpu", 0)

            # Avoid divide-by-zero
            cpu_percent = (cpu_usage / cpu_quota * 100) if cpu_quota else 0
            gpu_percent = (gpu_usage / gpu_quota * 100) if gpu_quota else 0

            # Check threshold
            if cpu_percent >= tres_percent or gpu_percent >= tres_percent:
                if record_type == "ACCOUNT":
                    print(
                        f"Account: {account}, "
                        f"{cpu_percent:.1f}%, {gpu_percent:.1f}%"
                    )
                else:  # USER
                    print(
                        f"Account/User: {account}/{user}, "
                        f"{cpu_percent:.1f}%, {gpu_percent:.1f}%"
                    )


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python script.py <tres_percent> <filename>")
        sys.exit(1)

    tres_percent = float(sys.argv[1])
    filename = sys.argv[2]

    process_file(tres_percent, filename)
