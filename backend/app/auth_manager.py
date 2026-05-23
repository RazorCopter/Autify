import json
import os
from datetime import datetime, timezone

# Utilizziamo la directory corrente dell'app per salvare i file JSON
APP_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_FILE = os.path.join(APP_DIR, "auth_config.json")
LOGS_FILE = os.path.join(APP_DIR, "viewer_logs.json")

DEFAULT_CONFIG = {
    "admin_pwd": "tiglio2026",
    "viewer_pwd": "tiglioviewer",
    "viewer_enabled": True
}

def get_auth_config():
    if not os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE, 'w', encoding='utf-8') as f:
            json.dump(DEFAULT_CONFIG, f, indent=4)
        return DEFAULT_CONFIG
    try:
        with open(CONFIG_FILE, 'r', encoding='utf-8') as f:
            return json.load(f)
    except Exception:
        return DEFAULT_CONFIG

def update_auth_config(new_config: dict):
    config = get_auth_config()
    if "admin_pwd" in new_config:
        config["admin_pwd"] = new_config["admin_pwd"]
    if "viewer_pwd" in new_config:
        config["viewer_pwd"] = new_config["viewer_pwd"]
    if "viewer_enabled" in new_config:
        config["viewer_enabled"] = new_config["viewer_enabled"]
    
    with open(CONFIG_FILE, 'w', encoding='utf-8') as f:
        json.dump(config, f, indent=4)
    return config

def get_viewer_logs():
    if not os.path.exists(LOGS_FILE):
        return []
    try:
        with open(LOGS_FILE, 'r', encoding='utf-8') as f:
            return json.load(f)
    except Exception:
        return []

def log_viewer_connection(ip_address: str, device_name: str):
    logs = get_viewer_logs()
    
    # Crea il nuovo record (datetime ISO)
    new_log = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "ip_address": ip_address,
        "device_name": device_name
    }
    
    # Inseriamo in testa per avere l'ordine cronologico inverso di base
    logs.insert(0, new_log)
    
    # Mantieni solo gli ultimi 1000 logs per non far esplodere il file
    if len(logs) > 1000:
        logs = logs[:1000]
        
    with open(LOGS_FILE, 'w', encoding='utf-8') as f:
        json.dump(logs, f, indent=4)
