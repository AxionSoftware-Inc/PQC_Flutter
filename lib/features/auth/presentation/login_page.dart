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
  String? _suggestedName;

  @override
  void initState() {
    super.initState();
    _primeSuggestion();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _primeSuggestion() async {
    final suggestedName = await widget.sessionController
        .suggestedBootstrapName();
    if (!mounted) {
      return;
    }
    setState(() {
      _suggestedName = suggestedName;
      if (_usernameController.text.trim().isEmpty) {
        _usernameController.text = suggestedName;
      }
    });
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final suggestedName = _suggestedName ?? 'Loading...';

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              colorScheme.surface,
              colorScheme.surfaceContainerHighest,
              colorScheme.primary.withValues(alpha: 0.12),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Card(
                elevation: 0,
                color: colorScheme.surface.withValues(alpha: 0.94),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(
                          Icons.shield_outlined,
                          color: colorScheme.onPrimaryContainer,
                          size: 30,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'PQC Messenger Workspace',
                        style: theme.textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Manual authni yengillashtirdim: shu qurilma uchun tayyor test profili bilan tez kirishingiz mumkin. Xohlasangiz nomni o\'zgartirasiz, qolgan kalitlar avtomatik biriktiriladi.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: colorScheme.secondaryContainer.withValues(
                            alpha: 0.5,
                          ),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.memory_rounded,
                              color: colorScheme.secondary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Recommended test profile: $suggestedName',
                                style: theme.textTheme.titleMedium,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _usernameController,
                        decoration: const InputDecoration(
                          labelText: 'Display name',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: _submit,
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: widget.sessionController.isLoading
                            ? null
                            : widget.sessionController.bootstrapLogin,
                        icon: const Icon(Icons.rocket_launch_outlined),
                        label: widget.sessionController.isLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Continue with this device'),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton(
                        onPressed: widget.sessionController.isLoading
                            ? null
                            : () => _submit(),
                        child: const Text('Use custom name'),
                      ),
                      if (widget.sessionController.error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          widget.sessionController.error!,
                          style: TextStyle(color: colorScheme.error),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
