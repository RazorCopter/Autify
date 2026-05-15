import 'package:flutter/material.dart';
import '../models/scale_model.dart';

class QuestionBuilder extends StatelessWidget {
  final Question question;
  final dynamic currentValue;
  final Function(dynamic) onChanged;

  const QuestionBuilder({
    super.key,
    required this.question,
    required this.currentValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            question.testoDomanda,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
          ),
          const SizedBox(height: 24),
          _buildInputWidget(context),
        ],
      ),
    );
  }

  Widget _buildInputWidget(BuildContext context) {
    switch (question.tipoRisposta) {
      case 'rating_1_to_5':
        return _buildRating1To5(context);
      case 'bool':
        return _buildBoolInput(context);
      // Espandibile in futuro con multiple_choice, test, ecc.
      default:
        return const Text('Tipo di risposta non supportato');
    }
  }

  Widget _buildRating1To5(BuildContext context) {
    int? currentRating = currentValue as int?;
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(5, (index) {
        final ratingValue = index + 1;
        final isSelected = currentRating == ratingValue;
        
        return InkWell(
          onTap: () => onChanged(ratingValue),
          borderRadius: BorderRadius.circular(50),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSelected 
                  ? Theme.of(context).colorScheme.primary 
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              border: Border.all(
                color: isSelected 
                    ? Theme.of(context).colorScheme.primary 
                    : Colors.transparent,
                width: 2,
              ),
            ),
            child: Center(
              child: Text(
                ratingValue.toString(),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isSelected 
                      ? Theme.of(context).colorScheme.onPrimary 
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildBoolInput(BuildContext context) {
    bool? currentBool = currentValue as bool?;

    return Row(
      children: [
        Expanded(
          child: RadioListTile<bool>(
            title: const Text("Sì"),
            value: true,
            groupValue: currentBool,
            onChanged: (val) => onChanged(val),
          ),
        ),
        Expanded(
          child: RadioListTile<bool>(
            title: const Text("No"),
            value: false,
            groupValue: currentBool,
            onChanged: (val) => onChanged(val),
          ),
        ),
      ],
    );
  }
}
