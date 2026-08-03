// join_by_code_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api_client.dart';
import '../validators.dart';
import 'league_detail_screen.dart';

class JoinByCodeScreen extends StatefulWidget {
  // Prefilled when this screen is opened from a rallyx://join/<code> deep
  // link — see deep_links.dart.
  final String? initialCode;

  const JoinByCodeScreen({super.key, this.initialCode});

  @override
  State<JoinByCodeScreen> createState() => _JoinByCodeScreenState();
}

class _JoinByCodeScreenState extends State<JoinByCodeScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _codeController = TextEditingController(
    text: widget.initialCode ?? '',
  );
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialCode != null && widget.initialCode!.isNotEmpty) {
      // Auto-submit — the user already tapped a link with intent to join,
      // no need to make them tap Join again.
      WidgetsBinding.instance.addPostFrameCallback((_) => _handleJoin());
    }
  }

  Future<void> _handleJoin() async {
    if (!_formKey.currentState!.validate()) return;
    final code = _codeController.text.trim();

    HapticFeedback.lightImpact();
    setState(() => _loading = true);

    try {
      final res = await ApiClient.post(
        '/leagues/join-by-code',
        body: {'code': code},
      );

      if (res.statusCode != 201) {
        _showAlert('Could not join', res.errorOr('Please try again.'));
        return;
      }

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => LeagueDetailScreen(leagueId: res.data['leagueId']),
        ),
      );
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
      appBar: AppBar(title: const Text('Join with Code')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Enter the join code shared by the tournament host.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _codeController,
              textCapitalization: TextCapitalization.characters,
              validator: (v) => requiredField(v, label: 'Join code'),
              decoration: const InputDecoration(
                labelText: 'Join Code',
                prefixIcon: Icon(Icons.key_outlined),
              ),
              style: const TextStyle(fontSize: 18, letterSpacing: 3),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loading ? null : _handleJoin,
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : const Text('Join Tournament'),
            ),
          ],
          ),
        ),
      ),
    );
  }
}
