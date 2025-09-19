import 'dart:io';
import 'package:kora/pages/call_page.dart';
import 'package:kora/pages/home_page.dart';
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
        MaterialPageRoute(builder: (context) => const HomePage()),
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: signupProvider.currentStep > 1
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.black),
                onPressed: () {
                  _pageController.previousPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                },
              )
            : null,
        title: Text(
          'Step ${signupProvider.currentStep} of 3',
          style: const TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          PageView(
            controller: _pageController,
            onPageChanged: (index) => signupProvider.currentStep = index + 1,
            children: [
              SignupStep1(
                onDataCollected: (name, age, image) {
                  signupProvider.setStep1Data(name, DateTime.now().subtract(Duration(days: age * 365)), image);
                  _pageController.nextPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                },
              ),
              SignupStep2(
                onDataCollected: (gender, interestedIn, location) {
                  signupProvider.setStep2Data(gender, interestedIn, location);
                  _pageController.nextPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                },
              ),
              SignupStep3(
                onDataCollected: (aboutMe) {
                  signupProvider.setStep3Data(aboutMe);
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
        ],
      ),
    );
  }
}
