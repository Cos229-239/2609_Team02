import 'package:flutter/material.dart';

import 'app_card.dart';

/// A labeled +/- stepper for a small non-negative integer amount.
class NumberStepper extends StatelessWidget {
  const NumberStepper({
    super.key,
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.onChanged,
    this.step = 5,
    this.min = 0,
    this.max = 1000,
  });

  final String label;
  final IconData icon;
  final Color iconColor;
  final int value;
  final ValueChanged<int> onChanged;
  final int step;
  final int min;
  final int max;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: iconColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: value <= min ? null : () => onChanged(value - step),
          ),
          SizedBox(
            width: 32,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: value >= max ? null : () => onChanged(value + step),
          ),
        ],
      ),
    );
  }
}
