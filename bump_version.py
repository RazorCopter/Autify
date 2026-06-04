import os
import re
import sys

def main():
    root_dir = os.path.dirname(os.path.abspath(__file__))
    version_file = os.path.join(root_dir, "VERSION")

    # Leggi o crea il file VERSION
    if not os.path.exists(version_file):
        print(f"File VERSION non trovato, creiamo con default: 2.18.10")
        with open(version_file, "w", encoding="utf-8") as f:
            f.write("2.18.10\n")
            
    with open(version_file, "r", encoding="utf-8") as f:
        new_version = f.read().strip()
        
    if not new_version:
        print("Il file VERSION è vuoto!")
        sys.exit(1)
        
    print(f"Aggiorno il progetto alla versione: {new_version}")

    # 1. Update backend/app/main.py
    backend_main = os.path.join(root_dir, "backend", "app", "main.py")
    if os.path.exists(backend_main):
        with open(backend_main, "r", encoding="utf-8") as f:
            content = f.read()
        content = re.sub(r'version="[\d\.]+"', f'version="{new_version}"', content)
        with open(backend_main, "w", encoding="utf-8") as f:
            f.write(content)
        print("OK: backend/app/main.py aggiornato.")

    # 2. Update frontend_admin/pubspec.yaml
    pubspec = os.path.join(root_dir, "frontend_admin", "pubspec.yaml")
    if os.path.exists(pubspec):
        with open(pubspec, "r", encoding="utf-8") as f:
            content = f.read()
        content = re.sub(r'^version:\s*[\d\.]+(?:\+.*)?', f'version: {new_version}', content, flags=re.MULTILINE)
        with open(pubspec, "w", encoding="utf-8") as f:
            f.write(content)
        print("OK: frontend_admin/pubspec.yaml aggiornato.")

    # 3. Update frontend_admin/lib/app_version.dart
    app_version_file = os.path.join(root_dir, "frontend_admin", "lib", "app_version.dart")
    if os.path.exists(app_version_file):
        with open(app_version_file, "r", encoding="utf-8") as f:
            content = f.read()
        content = re.sub(r"const String kFrontendVersion = '[\d\.]+';", f"const String kFrontendVersion = '{new_version}';", content)
        with open(app_version_file, "w", encoding="utf-8") as f:
            f.write(content)
        print("OK: frontend_admin/lib/app_version.dart aggiornato.")

    # 4. Update ARCHITECTURE_MAP.md
    arch_map = os.path.join(root_dir, "ARCHITECTURE_MAP.md")
    if os.path.exists(arch_map):
        with open(arch_map, "r", encoding="utf-8") as f:
            content = f.read()
        # Supporta sia il formato con asterischi (*v2.x.x*) che senza
        content = re.sub(
            r'(Single Source of Truth \(SSOT\) del Progetto — v)[\d\.]+',
            f'\\g<1>{new_version}',
            content
        )
        with open(arch_map, "w", encoding="utf-8") as f:
            f.write(content)
        print("OK: ARCHITECTURE_MAP.md aggiornato.")

    # 5. Update docker-compose.yml
    docker_compose = os.path.join(root_dir, "docker-compose.yml")
    if os.path.exists(docker_compose):
        with open(docker_compose, "r", encoding="utf-8") as f:
            content = f.read()
        content = re.sub(r'CACHE_BUST=[\d\.]+', f'CACHE_BUST={new_version}', content)
        with open(docker_compose, "w", encoding="utf-8") as f:
            f.write(content)
        print("OK: docker-compose.yml aggiornato.")

    print("\nFatto!")

if __name__ == "__main__":
    main()
