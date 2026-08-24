import os
import sys

try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        print("Error: tomllib (Python 3.11+) or tomli is required.", file=sys.stderr)
        sys.exit(1)

def load_config(config_dir: str):
    config_path = os.path.join(config_dir, "proxy.toml")
    if not os.path.exists(config_path):
        print(f"Warning: Config file not found at {config_path}", file=sys.stderr)
        return {}
    with open(config_path, "rb") as f:
        return tomllib.load(f)

def get_config():
    config_dir = os.environ.get("AGY_CONFIG_DIR", os.path.expanduser("~/.config/agy"))
    return load_config(config_dir)
