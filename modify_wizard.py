import sys

file_path = "frontend_admin/lib/screens/wizard_screen.dart"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# 1. Modify _buildOptionsList
build_options_list_target = """  Widget _buildOptionsList(_WizardItem item, bool isTablet) {
    if (_isSis3DQuestion(widget.scaleId, _currentKey)) {
      return _buildSis3DSelector(isTablet);
    }

    if (item.domanda.opzioni.isEmpty) {"""

build_options_list_replacement = """  Widget _buildOptionsList(_WizardItem item, bool isTablet) {
    if (_isSis3DQuestion(widget.scaleId, _currentKey)) {
      return _buildSis3DSelector(isTablet);
    }
    
    if (item.domanda.tipo == 'composito' && item.domanda.sottodomande != null) {
      return _buildChecklistOptions(item, isTablet);
    }

    if (item.domanda.opzioni.isEmpty) {"""

if build_options_list_target in content:
    content = content.replace(build_options_list_target, build_options_list_replacement)
else:
    print("Failed to find _buildOptionsList")
    sys.exit(1)

# 2. Inject _buildChecklistOptions
checklist_code = """
  Widget _buildChecklistOptions(_WizardItem item, bool isTablet) {
    final sottodomande = item.domanda.sottodomande!;
    final List<String> checkedStates = List<String>.from(_answers[_currentKey + '_checklist'] ?? []);

    return Column(
      children: sottodomande.asMap().entries.map((entry) {
        final idx = entry.key;
        final subq = entry.value;
        final testo = subq['testo'] ?? '';
        final isChecked = checkedStates.contains(testo);

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            onTap: () {
              setState(() {
                if (isChecked) {
                  checkedStates.remove(testo);
                } else {
                  checkedStates.add(testo);
                }
                _answers[_currentKey + '_checklist'] = checkedStates;
                _answers[_currentKey] = checkedStates.length;
              });
              _requestKeyboardFocus();
            },
            borderRadius: BorderRadius.circular(16),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              padding: EdgeInsets.symmetric(
                vertical: isTablet ? 18 : 14,
                horizontal: isTablet ? 24 : 16,
              ),
              decoration: BoxDecoration(
                color: isChecked
                    ? AppTheme.primaryColor.withOpacity(0.08)
                    : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isChecked
                      ? AppTheme.primaryColor
                      : AppTheme.borderLight,
                  width: isChecked ? 2 : 1,
                ),
                boxShadow: isChecked
                    ? [
                        BoxShadow(
                          color: AppTheme.primaryColor.withOpacity(0.15),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        )
                      ]
                    : [],
              ),
              child: Row(
                children: [
                  Icon(
                    isChecked ? Icons.check_box : Icons.check_box_outline_blank,
                    color: isChecked ? AppTheme.primaryColor : AppTheme.textSecondary,
                    size: 28,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      testo,
                      style: TextStyle(
                        fontSize: isTablet ? 17 : 15,
                        fontWeight: isChecked ? FontWeight.w600 : FontWeight.w500,
                        color: isChecked ? AppTheme.primaryColor : AppTheme.textPrimary,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
"""

# Find where to inject (before _buildOptionButton)
if "  Widget _buildOptionButton" in content:
    content = content.replace("  Widget _buildOptionButton", checklist_code + "\n  Widget _buildOptionButton")
else:
    print("Failed to find _buildOptionButton")
    sys.exit(1)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)

print("Modification successful.")
