import 'dart:io';
import 'package:kora/pages/call_page.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/signup_provider.dart';
import '../widgets/custom_progress_bar.dart';
import '../widgets/signup_step1.dart';
import '../widgets/signup_step2.dart';
import '../widgets/signup_step3.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _pageController = PageController();

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _handleSave(SignupProvider provider) async {
    try {
      await provider.saveUser();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const CallPage()),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving profile: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final signupProvider = Provider.of<SignupProvider>(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Sign Up')),
      body: Stack(
        children: [
          PageView(
            controller: _pageController,
            onPageChanged: (index) => signupProvider.currentStep = index + 1,
            children: [
              SignupStep1(
                onDataCollected: (name, age, image) {
                  signupProvider.addData({
                    'name': name,
                    'age': age,
                    'profile_picture': image.path,
                  });
                  _pageController.nextPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                },
              ),
              SignupStep2(
                onDataCollected: (gender, genderPreference, location) {
                  signupProvider.addData({
                    'gender': gender,
                    'gender_preference': genderPreference,
                    'location': location,
                  });
                  _pageController.nextPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                },
              ),
              SignupStep3(
                onDataCollected: (aboutMe) {
                  signupProvider.addData({'aboutMe': aboutMe});
                  _handleSave(signupProvider);
                },
              ),
            ],
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: CustomProgressBar(currentStep: signupProvider.currentStep),
          ),
          Positioned(
            bottom: 60,
            right: 16,
            child: Row(
              children: [
                if (signupProvider.currentStep > 1)
                  ElevatedButton(
                    onPressed: () {
                      _pageController.previousPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    },
                    child: const Text('Back'),
                  ),
                if (signupProvider.currentStep < 3) const SizedBox(width: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
