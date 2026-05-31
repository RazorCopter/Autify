import os
import datetime

today = datetime.datetime.now().strftime('%Y-%m-%d')
changelog_entry = f\"\"\"## [2.18.32] - {today}
### Changed
- Improved dynamic item-to-domain mapping in nalytics.py for custom scales like SABS.
- Renamed UI section 'Comportamenti Specifici' to 'Comportamento Adattivo' in multidimensional dashboard.
- Display custom scale names dynamically in dashboard scale cards instead of hardcoded text.

\"\"\"

with open('CHANGELOG.md', 'r', encoding='utf-8') as f:
    content = f.read()

# Insert after the first '# Changelog' or similar header
insert_pos = content.find('## [')
if insert_pos != -1:
    content = content[:insert_pos] + changelog_entry + content[insert_pos:]
else:
    content = '# Changelog\n\n' + changelog_entry + content

with open('CHANGELOG.md', 'w', encoding='utf-8') as f:
    f.write(content)
