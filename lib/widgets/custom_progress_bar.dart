import 'package:flutter/material.dart';

class CustomProgressBar extends StatelessWidget {
  final int currentStep;

  const CustomProgressBar({required this.currentStep, super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildBar(1 <= currentStep),
        const SizedBox(width: 8),
        _buildBar(2 <= currentStep),
        const SizedBox(width: 8),
        _buildBar(3 <= currentStep),
      ],
    );
  }

  Widget _buildBar(bool isActive) {
    return Container(
      width: 40,
      height: 8,
      decoration: BoxDecoration(
        color: isActive ? Colors.black : Colors.grey,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
