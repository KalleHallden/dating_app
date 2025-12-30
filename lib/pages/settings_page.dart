import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/account_deletion_service.dart';
import '../services/supabase_client.dart';
import 'welcome_screen.dart';
import 'contact_form_page.dart';
import 'blocked_users_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({Key? key}) : super(key: key);

  Future<void> _launchUrl(BuildContext context, String urlString) async {
    final url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open link')),
        );
      }
    }
  }

  Future<void> _handleSignOut(BuildContext context) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Sign Out'),
          content: const Text('Are you sure you want to sign out?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF985021),
              ),
              child: const Text('Sign Out'),
            ),
          ],
        );
      },
    );

    if (confirmed == true && context.mounted) {
      try {
        await SupabaseClient.instance.client.auth.signOut();
        if (context.mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const WelcomeScreen()),
            (route) => false,
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error signing out: $e')),
          );
        }
      }
    }
  }

  Future<void> _showDeleteAccountDialog(BuildContext context) async {
    final TextEditingController reasonController = TextEditingController();
    bool isDeleting = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.warning, color: Colors.orange, size: 28),
                  SizedBox(width: 8),
                  Text('Delete Account'),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Are you sure you want to delete your account?',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '� Important:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text('" All your data will be permanently deleted'),
                          Text('" Your matches and messages will be removed'),
                          Text('" You may not be able to create a new account immediately'),
                          Text('" There may be a cooldown period before you can register again'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Optional: Tell us why you\'re leaving',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: reasonController,
                      decoration: InputDecoration(
                        hintText: 'Your feedback helps us improve...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      maxLines: 3,
                      enabled: !isDeleting,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isDeleting
                      ? null
                      : () {
                          reasonController.dispose();
                          Navigator.of(dialogContext).pop();
                        },
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isDeleting
                      ? null
                      : () async {
                          // Show second confirmation
                          final bool? confirmed = await showDialog<bool>(
                            context: context,
                            builder: (BuildContext context) {
                              return AlertDialog(
                                title: const Text('Final Confirmation'),
                                content: const Text(
                                  'This action cannot be undone. Are you absolutely sure you want to delete your account?',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(context).pop(false),
                                    child: const Text('No, keep my account'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () => Navigator.of(context).pop(true),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red,
                                    ),
                                    child: const Text('Yes, delete my account'),
                                  ),
                                ],
                              );
                            },
                          );

                          if (confirmed == true) {
                            setDialogState(() {
                              isDeleting = true;
                            });

                            // Call the deletion service
                            final result = await AccountDeletionService().deleteAccount(
                              reason: reasonController.text.trim().isNotEmpty
                                  ? reasonController.text.trim()
                                  : null,
                            );

                            if (!context.mounted) return;

                            if (result.success) {
                              // Show success message with cooldown info
                              await showDialog(
                                context: context,
                                barrierDismissible: false,
                                builder: (BuildContext context) {
                                  return AlertDialog(
                                    icon: const Icon(
                                      Icons.check_circle,
                                      color: Colors.green,
                                      size: 48,
                                    ),
                                    title: const Text('Account Deleted'),
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(result.message ?? 'Your account has been successfully deleted.'),
                                        if (result.cooldownDays != null) ...[
                                          const SizedBox(height: 16),
                                          Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: Colors.blue.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              result.getCooldownMessage(),
                                              style: const TextStyle(fontSize: 14),
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                        ],
                                        if (result.canReregisterAfter != null) ...[
                                          const SizedBox(height: 8),
                                          Text(
                                            'Available from: ${result.getReregisterDateFormatted()}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    actions: [
                                      ElevatedButton(
                                        onPressed: () async {
                                          // Sign out and navigate to welcome screen
                                          await AccountDeletionService().signOutAfterDeletion();
                                          if (context.mounted) {
                                            Navigator.of(context).pushAndRemoveUntil(
                                              MaterialPageRoute(
                                                builder: (context) => const WelcomeScreen(),
                                              ),
                                              (route) => false,
                                            );
                                          }
                                        },
                                        child: const Text('OK'),
                                      ),
                                    ],
                                  );
                                },
                              );
                            } else {
                              // Handle error
                              Navigator.of(dialogContext).pop();

                              String errorTitle = 'Deletion Failed';
                              IconData errorIcon = Icons.error_outline;
                              Color errorColor = Colors.red;

                              if (result.isAlreadyDeleted) {
                                errorTitle = 'Account Already Deleted';
                                errorIcon = Icons.info_outline;
                                errorColor = Colors.orange;
                              }

                              await showDialog(
                                context: context,
                                builder: (BuildContext context) {
                                  return AlertDialog(
                                    icon: Icon(
                                      errorIcon,
                                      color: errorColor,
                                      size: 48,
                                    ),
                                    title: Text(errorTitle),
                                    content: Text(
                                      result.error ?? 'Failed to delete account. Please try again.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.of(context).pop(),
                                        child: const Text('OK'),
                                      ),
                                    ],
                                  );
                                },
                              );
                            }

                            reasonController.dispose();
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                  ),
                  child: isDeleting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text('Delete Account'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildSettingsTile({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
    bool showChevron = true,
    Color? textColor,
    Color? iconColor,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Colors.grey[300]!,
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 24,
              color: iconColor ?? Colors.grey[700],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  color: textColor ?? Colors.black87,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            if (showChevron)
              Icon(
                Icons.chevron_right,
                color: Colors.grey[400],
                size: 24,
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Settings'),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
      ),
      body: Column(
        children: [
          const SizedBox(height: 8),
          // Links Section
          Container(
            color: Colors.white,
            child: Column(
              children: [
                _buildSettingsTile(
                  title: 'Terms of Service',
                  icon: Icons.description_outlined,
                  onTap: () => _launchUrl(context, 'https://koradating.com/terms-of-service/'),
                ),
                _buildSettingsTile(
                  title: 'Privacy Policy',
                  icon: Icons.privacy_tip_outlined,
                  onTap: () => _launchUrl(context, 'https://koradating.com/privacy-policy/'),
                ),
                _buildSettingsTile(
                  title: 'Community Guidelines',
                  icon: Icons.people_outline,
                  onTap: () => _launchUrl(context, 'https://koradating.com/community-guidelines/'),
                ),
                _buildSettingsTile(
                  title: 'Contact Us',
                  icon: Icons.email_outlined,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ContactFormPage(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Privacy & Safety Section
          Container(
            color: Colors.white,
            child: Column(
              children: [
                _buildSettingsTile(
                  title: 'Blocked Users',
                  icon: Icons.block,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const BlockedUsersPage(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Account Actions Section
          Container(
            color: Colors.white,
            child: Column(
              children: [
                _buildSettingsTile(
                  title: 'Sign Out',
                  icon: Icons.logout,
                  onTap: () => _handleSignOut(context),
                  showChevron: false,
                  textColor: Colors.black87,
                  iconColor: Colors.grey[700],
                ),
                _buildSettingsTile(
                  title: 'Delete Account',
                  icon: Icons.delete_forever,
                  onTap: () => _showDeleteAccountDialog(context),
                  showChevron: false,
                  textColor: Colors.red,
                  iconColor: Colors.red,
                ),
              ],
            ),
          ),
          const Spacer(),
          // Version info
          Padding(
            padding: const EdgeInsets.only(bottom: 32.0),
            child: Text(
              'Version 1.0.0',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
