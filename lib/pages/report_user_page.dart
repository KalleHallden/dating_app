import 'package:flutter/material.dart';
import '../services/supabase_client.dart';
import 'home_page.dart';

class ReportUserPage extends StatefulWidget {
  final String reportedUserId;
  final String reportedUserName;
  final String? reportedUserProfilePicture;

  const ReportUserPage({
    Key? key,
    required this.reportedUserId,
    required this.reportedUserName,
    this.reportedUserProfilePicture,
  }) : super(key: key);

  @override
  State<ReportUserPage> createState() => _ReportUserPageState();
}

class _ReportUserPageState extends State<ReportUserPage> {
  final _formKey = GlobalKey<FormState>();
  String? _selectedReason;
  final TextEditingController _additionalDetailsController =
      TextEditingController();
  bool _isSubmitting = false;

  // Industry standard report reasons
  final List<String> _reportReasons = [
    'Inappropriate behavior',
    'Harassment or bullying',
    'Hate speech or discrimination',
    'Sexual content or nudity',
    'Violence or threats',
    'Spam or commercial content',
    'Fake profile or catfishing',
    'Underage user',
    'Other'
  ];

  @override
  void dispose() {
    _additionalDetailsController.dispose();
    super.dispose();
  }

  Future<void> _submitReport() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedReason == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a reason for reporting'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final client = SupabaseClient.instance.client;
      final currentUser = client.auth.currentUser;

      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      final response = await client.functions.invoke(
        'report-user',
        body: {
          'reporter_id': currentUser.id,
          'reported_user_id': widget.reportedUserId,
          'reason': _selectedReason,
          'additional_details': _additionalDetailsController.text.trim().isEmpty
              ? null
              : _additionalDetailsController.text.trim(),
        },
      );

      if (response.status != 200) {
        throw Exception('Failed to submit report: ${response.data}');
      }

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const ReportThankYouPage(),
          ),
        );
      }
    } catch (e) {
      setState(() => _isSubmitting = false);

      if (mounted) {
        String errorMessage = 'Failed to submit report';

        // Parse the error message to provide user-friendly feedback
        if (e.toString().contains('already reported this user in the last 24 hours')) {
          errorMessage = 'You have already reported this user recently. Please wait 24 hours before submitting another report.';
        } else if (e.toString().contains('cannot report themselves')) {
          errorMessage = 'You cannot report yourself.';
        } else if (e.toString().contains('Missing required fields')) {
          errorMessage = 'Please select a reason for your report.';
        } else {
          errorMessage = 'Failed to submit report. Please try again later.';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Report User'),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const HomePage()),
              (route) => false,
            );
          },
        ),
      ),
      body: _isSubmitting
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Submitting report...'),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // User info section
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 24,
                              backgroundColor: Colors.grey[300],
                              backgroundImage:
                                  widget.reportedUserProfilePicture != null &&
                                          widget.reportedUserProfilePicture!
                                              .isNotEmpty
                                      ? NetworkImage(
                                          widget.reportedUserProfilePicture!)
                                      : null,
                              child: widget.reportedUserProfilePicture ==
                                          null ||
                                      widget.reportedUserProfilePicture!.isEmpty
                                  ? Text(
                                      widget.reportedUserName.isNotEmpty
                                          ? widget.reportedUserName[0]
                                              .toUpperCase()
                                          : '?',
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey,
                                      ),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'You are reporting:',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  widget.reportedUserName,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Report reason section
                    const Text(
                      'What happened?',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Please select the reason that best describes the issue:',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Report reasons list
                    ..._reportReasons.map((reason) => RadioListTile<String>(
                          title: Text(reason),
                          value: reason,
                          groupValue: _selectedReason,
                          onChanged: (value) {
                            setState(() {
                              _selectedReason = value;
                            });
                          },
                          activeColor: Colors.red,
                        )),

                    const SizedBox(height: 24),

                    // Additional details section
                    const Text(
                      'Additional details (optional)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _additionalDetailsController,
                      maxLines: 4,
                      maxLength: 500,
                      decoration: const InputDecoration(
                        hintText:
                            'Please provide any additional details that might help us understand the situation...',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value != null && value.length > 500) {
                          return 'Details cannot exceed 500 characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),

                    // Important notice
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange[200]!),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.orange[700],
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'All reports are taken seriously and will be reviewed by our team. False reports may result in action against your account.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange[700],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Submit button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submitReport,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'Submit Report',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class ReportThankYouPage extends StatelessWidget {
  const ReportThankYouPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Success icon
              Container(
                width: 80,
                height: 80,
                decoration: const BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check,
                  color: Colors.white,
                  size: 40,
                ),
              ),
              const SizedBox(height: 32),

              // Thank you message
              const Text(
                'Thank You!',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              const Text(
                'Thank you for reporting this user and helping to keep this platform safe and fun.',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              const Text(
                'Our team will review your report and take appropriate action. You may not receive a direct response, but we appreciate you looking out for our community.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),

              // Return to home button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const HomePage()),
                      (route) => false,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Back to Home',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
