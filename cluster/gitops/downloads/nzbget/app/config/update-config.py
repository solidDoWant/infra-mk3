#!/usr/bin/env python3
import string
import sys
import os


def update_config(baseline_path, override_path, output_path):
    """Update baseline config with overrides."""
    # Read override key-value pairs
    overrides = {}
    with open(override_path, 'r') as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#') and '=' in line:
                key, value = line.split('=', 1)
                overrides[key] = string.Template(value).substitute(os.environ)

    # Read baseline and apply overrides
    lines = []
    used_keys = set()

    with open(baseline_path, 'r') as f:
        for line in f:
            stripped = line.strip()
            if stripped and not stripped.startswith('#') and '=' in stripped:
                key = stripped.split('=', 1)[0]
                if key in overrides:
                    lines.append(f"{key}={overrides[key]}\n")
                    used_keys.add(key)
                else:
                    lines.append(line)
            else:
                lines.append(line)

    # Add new keys
    for key, value in overrides.items():
        if key not in used_keys:
            lines.append(f"{key}={value}\n")

    # Write result to output file
    with open(output_path, 'w') as f:
        f.writelines(lines)

    os.chmod(output_path, 0o660)


if __name__ == "__main__":
    baseline_path = os.environ.get("BASELINE_CONFIG_FILE_PATH")
    override_path = os.environ.get("OVERRIDE_CONFIG_FILE_PATH")
    output_path = os.environ.get("OUTPUT_CONFIG_FILE_PATH")

    exit = False
    if not baseline_path:
        print("Error: BASELINE_CONFIG_FILE_PATH environment variable not set")
        exit = True

    if not override_path:
        print("Error: OVERRIDE_CONFIG_FILE_PATH environment variable not set")
        exit = True

    if not output_path:
        print("Error: OUTPUT_CONFIG_FILE_PATH environment variable not set")
        exit = True

    if exit:
        sys.exit(1)

    update_config(baseline_path, override_path, output_path)
    print(f"Updated config written to {output_path}")
