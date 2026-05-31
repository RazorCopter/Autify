import os

files = [
    'backend/app/main.py',
    'ARCHITECTURE_MAP.md',
    'docker-compose.yml',
    'frontend_admin/lib/app_version.dart',
    'frontend_admin/pubspec.yaml',
    'VERSION'
]

for file in files:
    with open(file, 'r', encoding='utf-8') as f:
        content = f.read()
    content = content.replace('2.18.31', '2.18.32')
    with open(file, 'w', encoding='utf-8') as f:
        f.write(content)
