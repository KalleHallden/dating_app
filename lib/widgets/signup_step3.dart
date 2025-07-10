import 'package:flutter/material.dart';

class SignupStep3 extends StatefulWidget {
  final Function(String aboutMe) onDataCollected;

  const SignupStep3({required this.onDataCollected, super.key});

  @override
  State<SignupStep3> createState() => _SignupStep3State();
}

class _SignupStep3State extends State<SignupStep3> {
  final _aboutController = TextEditingController();

  @override
  void dispose() {
    _aboutController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _aboutController,
            decoration: const InputDecoration(labelText: 'About Me'),
            maxLines: 4,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              if (_aboutController.text.isNotEmpty) {
                widget.onDataCollected(_aboutController.text);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('About Me is required')),
                );
              }
            },
            child: const Text('Finish'),
          ),
        ],
      ),
    );
  }
}
