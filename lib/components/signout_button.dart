// lib/widgets/signout_button.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import '../pages/auth_screen.dart';
import '../services/supabase_client.dart';

class SignoutButton extends StatefulWidget {
  final String? text;
  final IconData? icon;
  final Color? backgroundColor;
  final Color? textColor;
  final EdgeInsetsGeometry? padding;
  final double? fontSize;
  final bool showIcon;
  final bool showConfirmDialog;
  final ButtonStyle? customStyle;

  const SignoutButton({
    Key? key,
    this.text,
    this.icon,
    this.backgroundColor,
    this.textColor,
    this.padding,
    this.fontSize,
    this.showIcon = true,
    this.showConfirmDialog = true,
    this.customStyle,
  }) : super(key: key);

  @override
  State<SignoutButton> createState() => _SignoutButtonState();
}

class _SignoutButtonState extends State<SignoutButton> {
  bool _isSigningOut = false;

  Future<void> _handleSignout() async {
    // Show confirmation dialog if enabled
    if (widget.showConfirmDialog) {
      final shouldSignOut = await _showConfirmDialog();
      if (!shouldSignOut) return;
    }

    setState(() {
      _isSigningOut = true;
    });

    try {
      // Sign out from Supabase
      await SupabaseClient.instance.client.auth.signOut();
      
      // Navigate to AuthScreen and clear the navigation stack
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) => const AuthScreen(
              initialMessage: 'Successfully signed out. Please sign in again.',
            ),
          ),
          (_) => false, // Remove all previous routes
        );
      }
    } catch (e) {
      print('Error during signout: $e');
      
      // Show error message to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error signing out: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSigningOut = false;
        });
      }
    }
  }

  Future<bool> _showConfirmDialog() async {
    return await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Sign Out'),
          content: const Text('Are you sure you want to sign out?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
              ),
              child: const Text('Sign Out'),
            ),
          ],
        );
      },
    ) ?? false;
  }

  @override
  Widget build(BuildContext context) {
    // Default styling
    final defaultBackgroundColor = widget.backgroundColor ?? Colors.red;
    final defaultTextColor = widget.textColor ?? Colors.white;
    final defaultText = widget.text ?? 'Sign Out';
    final defaultIcon = widget.icon ?? Icons.logout;
    final defaultFontSize = widget.fontSize ?? 16.0;

    // Create button content
    Widget buttonContent;
    
    if (_isSigningOut) {
      buttonContent = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(defaultTextColor),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Signing out...',
            style: TextStyle(
              color: defaultTextColor,
              fontSize: defaultFontSize,
            ),
          ),
        ],
      );
    } else if (widget.showIcon) {
      buttonContent = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(defaultIcon, color: defaultTextColor, size: defaultFontSize + 2),
          const SizedBox(width: 8),
          Text(
            defaultText,
            style: TextStyle(
              color: defaultTextColor,
              fontSize: defaultFontSize,
            ),
          ),
        ],
      );
    } else {
      buttonContent = Text(
        defaultText,
        style: TextStyle(
          color: defaultTextColor,
          fontSize: defaultFontSize,
        ),
      );
    }

    // Use custom style if provided, otherwise use default
    final buttonStyle = widget.customStyle ?? ElevatedButton.styleFrom(
      backgroundColor: defaultBackgroundColor,
      foregroundColor: defaultTextColor,
      padding: widget.padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    );

    return ElevatedButton(
      onPressed: _isSigningOut ? null : _handleSignout,
      style: buttonStyle,
      child: buttonContent,
    );
  }
}

// Convenience variants for common use cases
class SignoutIconButton extends StatelessWidget {
  final Color? iconColor;
  final double? iconSize;
  final bool showConfirmDialog;

  const SignoutIconButton({
    Key? key,
    this.iconColor,
    this.iconSize,
    this.showConfirmDialog = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SignoutButton(
      showIcon: true,
      text: '',
      backgroundColor: Colors.transparent,
      textColor: iconColor ?? Colors.red,
      fontSize: iconSize ?? 24,
      showConfirmDialog: showConfirmDialog,
      customStyle: ElevatedButton.styleFrom(
        backgroundColor: Colors.transparent,
        shadowColor: Colors.transparent,
        padding: const EdgeInsets.all(8),
        minimumSize: const Size(40, 40),
      ),
    );
  }
}

class SignoutTextButton extends StatelessWidget {
  final String? text;
  final Color? textColor;
  final bool showConfirmDialog;

  const SignoutTextButton({
    Key? key,
    this.text,
    this.textColor,
    this.showConfirmDialog = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SignoutButton(
      text: text ?? 'Sign Out',
      showIcon: false,
      backgroundColor: Colors.transparent,
      textColor: textColor ?? Colors.red,
      showConfirmDialog: showConfirmDialog,
      customStyle: ElevatedButton.styleFrom(
        backgroundColor: Colors.transparent,
        shadowColor: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
    );
  }
}
