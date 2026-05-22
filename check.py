import os
import re

def check_imports(directory):
    pattern = re.compile(r"import\s+['\"]([^'\"]+\.dart)['\"]")
    has_error = False
    for root, dirs, files in os.walk(directory):
        for f in files:
            if f.endswith('.dart'):
                filepath = os.path.join(root, f)
                with open(filepath, 'r', encoding='utf-8') as file:
                    content = file.read()
                    for match in pattern.findall(content):
                        if not match.startswith('package:') and not match.startswith('dart:'):
                            target_path = os.path.normpath(os.path.join(root, match))
                            # os.path.exists on Windows is case-insensitive, so we must check exact case
                            target_dir = os.path.dirname(target_path)
                            target_file = os.path.basename(target_path)
                            
                            if os.path.exists(target_dir):
                                actual_files = os.listdir(target_dir)
                                if target_file not in actual_files:
                                    print(f"CASE MISMATCH: {match} in {filepath} (Actual files: {actual_files})")
                                    has_error = True
                            else:
                                print(f"MISSING DIR: {match} in {filepath}")
                                has_error = True
    if not has_error:
        print("All imports case-match correctly!")

check_imports('frontend_admin/lib')
