import 'package:flutter/material.dart';

import '../session_controller.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.sessionController});

  final SessionController sessionController;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _usernameController = TextEditingController();

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _submit([String? username]) async {
    final value = (username ?? _usernameController.text).trim();
    if (value.isEmpty) {
      return;
    }

    await widget.sessionController.login(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PQC Chat Login')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Ismingizni kiriting. Qurilma identifikatori avtomatik biriktiriladi.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'Ism',
                border: OutlineInputBorder(),
              ),
              onSubmitted: _submit,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: widget.sessionController.isLoading
                  ? null
                  : () => _submit(),
              child: widget.sessionController.isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Login'),
            ),
            if (widget.sessionController.error != null) ...[
              const SizedBox(height: 12),
              Text(
                widget.sessionController.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
