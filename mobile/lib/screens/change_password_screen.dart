// change_password_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final TextEditingController _currentController = TextEditingController();
  final TextEditingController _newController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  bool _loading = false;

  Future<void> _handleChange() async {
    final current = _currentController.text;
    final newPass = _newController.text;
    final confirm = _confirmController.text;

    if (current.isEmpty || newPass.isEmpty || confirm.isEmpty) {
      _showAlert('Missing fields', 'Please fill in all fields.');
      return;
    }
    if (newPass.length < 6) {
      _showAlert(
        'Weak password',
        'New password must be at least 6 characters.',
      );
      return;
    }
    if (newPass != confirm) {
      _showAlert('Mismatch', 'New password and confirmation do not match.');
      return;
    }

    HapticFeedback.lightImpact();
    setState(() => _loading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('authToken');

      final response = await http.patch(
        Uri.parse('$baseApiUrl/auth/change-password'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'currentPassword': current, 'newPassword': newPass}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode != 200) {
        _showAlert(
          'Something went wrong',
          data['error'] ?? 'Please try again.',
        );
        return;
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (err) {
      _showAlert('Network error', 'Could not reach the server.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showAlert(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Change Password')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _currentController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Current Password',
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _newController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'New Password',
                prefixIcon: Icon(Icons.lock_reset),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _confirmController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Confirm New Password',
                prefixIcon: Icon(Icons.lock_reset),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loading ? null : _handleChange,
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : const Text('Update Password'),
            ),
          ],
        ),
      ),
    );
  }
}
