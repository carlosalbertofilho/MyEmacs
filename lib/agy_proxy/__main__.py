import sys
import os
import argparse
from aiohttp import web

from agy_proxy.config import get_config
from agy_proxy.server import create_app

def parse_args():
    parser = argparse.ArgumentParser(description="AGY HTTP Proxy")
    parser.add_argument("--port", type=int, default=8088)
    parser.add_argument("--log-format", type=str, default="json")
    return parser.parse_args()

def main():
    args = parse_args()
    config = get_config()
    
    # Merge CLI args into config
    if "server" not in config:
        config["server"] = {}
    config["server"]["port"] = args.port
    config["server"]["log_format"] = args.log_format
    
    port = config["server"].get("port", 8088)
    host = config["server"].get("host", "127.0.0.1")
    
    app = create_app(config)
    web.run_app(app, host=host, port=port)
    return 0

if __name__ == "__main__":
    sys.exit(main())
