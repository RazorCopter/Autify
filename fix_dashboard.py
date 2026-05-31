import sys

file_path = r"c:\Users\gianv\Documents\Progetti\autify\AutAnalysis\frontend_admin\lib\screens\multidimensional_dashboard_screen.dart"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# Fix the missing parenthesis
bad_line = """      final accentGradient = isSis
          ? const [Color(0xFF00695C), Color(0xFF26A69A)] // Teal premium per la scala SIS
          : (isBehavior ? const [Color(0xFF6A1B9A), Color(0xFFAB47BC)] : (isSM
              ? const [Color(0xFF1A237E), Color(0xFF3949AB)]
              : const [Color(0xFF0D47A1), Color(0xFF42A5F5)]);"""

good_line = """      final accentGradient = isSis
          ? const [Color(0xFF00695C), Color(0xFF26A69A)] // Teal premium per la scala SIS
          : isBehavior ? const [Color(0xFF6A1B9A), Color(0xFFAB47BC)] : isSM
              ? const [Color(0xFF1A237E), Color(0xFF3949AB)]
              : const [Color(0xFF0D47A1), Color(0xFF42A5F5)];"""

if bad_line in content:
    content = content.replace(bad_line, good_line)
else:
    print("Could not find bad_line")
    sys.exit(1)

# Add _isBehaviorScale if it's missing at the class level
if "bool _isBehaviorScale(" not in content:
    target_method = "  bool _isSisScale(String id, String nome) {"
    replacement = """  bool _isBehaviorScale(String id, String nome) {
    final lowerId = id.toLowerCase();
    final lowerNome = nome.toLowerCase();
    return lowerId.contains('sabs') || lowerId.contains('behavior') || lowerId.contains('comportament') ||
           lowerNome.contains('sabs') || lowerNome.contains('behavior') || lowerNome.contains('comportament');
  }

  bool _isSisScale(String id, String nome) {"""
    if target_method in content:
        content = content.replace(target_method, replacement)
    else:
        print("Could not find target_method _isSisScale")
        sys.exit(1)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)

print("Modification successful.")
