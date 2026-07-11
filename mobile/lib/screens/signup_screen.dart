// signup_screen.dart
// Place this in lib/screens/signup_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const String apiUrl = 'http://192.168.0.105:3000/api/auth';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _loading = false;

  Future<void> _handleSignup() async {
    final username = _usernameController.text.trim();
    final phoneNumber = _phoneController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty || phoneNumber.isEmpty || password.isEmpty) {
      _showAlert('Missing fields', 'Please fill in all fields.');
      return;
    }
    if (password.length < 6) {
      _showAlert('Weak password', 'Password must be at least 6 characters.');
      return;
    }
    if (!RegExp(r'^\d{10}$').hasMatch(phoneNumber)) {
      _showAlert('Invalid number', 'Enter a valid 10-digit mobile number.');
      return;
    }

    setState(() => _loading = true);

    try {
      final response = await http.post(
        Uri.parse('$apiUrl/signup'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'phoneNumber': phoneNumber,
          'password': password,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode != 201) {
        _showAlert('Signup failed', data['error'] ?? 'Something went wrong.');
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('authToken', data['token']);
      await prefs.setString('user', jsonEncode(data['user']));

      if (!mounted) return;
      // New users should pick which sports they play next.
      // For now, until that screen exists, send them to Home.
      Navigator.pushReplacementNamed(context, '/select-sports');
    } catch (err) {
      _showAlert(
        'Network error',
        'Could not reach the server. Check your connection.',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showAlert(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
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
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Create Account',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
                  decoration: const InputDecoration(
                    labelText: 'Mobile Number',
                    border: OutlineInputBorder(),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _loading ? null : _handleSignup,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('Sign Up', style: TextStyle(fontSize: 16)),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => Navigator.pushNamed(context, '/login'),
                  child: const Text('Already have an account? Log in'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
