import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/config.dart';
import 'auth_controller.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocusNode = FocusNode();
  String _selectedCompany = 'Prosmart Erp';

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final auth = ref.read(authControllerProvider);
    if (auth.isLoading) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await ref.read(authControllerProvider.notifier).login(
          username: _usernameController.text,
          password: _passwordController.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    ref.listen(authControllerProvider, (_, next) {
      if (next.hasError) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.error.toString())));
      }
      if (next.asData?.value != null) {
        context.go('/');
      }
    });

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFFF7F9FB),
              scheme.surface,
              const Color(0xFFEAF2F7),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 760;
                    final brand = _BrandPanel(isWide: isWide);
                    final form = _LoginCard(
                      formKey: _formKey,
                      selectedCompany: _selectedCompany,
                      usernameController: _usernameController,
                      passwordController: _passwordController,
                      passwordFocusNode: _passwordFocusNode,
                      isLoading: auth.isLoading,
                      onCompanyChanged: (value) => setState(
                        () => _selectedCompany = value ?? 'Prosmart Erp',
                      ),
                      onSubmit: _submit,
                      onClear: () {
                        _usernameController.clear();
                        _passwordController.clear();
                        setState(() {});
                      },
                    );

                    if (!isWide) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          brand,
                          const SizedBox(height: 16),
                          form,
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: brand),
                        const SizedBox(width: 16),
                        SizedBox(width: 390, child: form),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel({required this.isWide});

  final bool isWide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      constraints: BoxConstraints(minHeight: isWide ? 420 : 180),
      padding: EdgeInsets.all(isWide ? 32 : 24),
      decoration: BoxDecoration(
        color: const Color(0xFF253444),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F000000),
            blurRadius: 24,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _ProsmartLogoMark(compact: !isWide),
          if (isWide) ...[
            const SizedBox(height: 56),
            Text(
              'Kasa, şube ve muhasebe kontrolü',
              style: theme.textTheme.headlineMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Günlük satış aktarımı, icmal ve onay akışı tek ekranda.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: Colors.white70,
                height: 1.45,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.verified_outlined, color: scheme.tertiary),
                  const SizedBox(width: 8),
                  const Text(
                    'Prosmart Erp',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProsmartLogoMark extends StatelessWidget {
  const _ProsmartLogoMark({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: compact ? 44 : 52,
          height: compact ? 44 : 52,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.grid_view_rounded,
            color: Color(0xFF253444),
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Prosmart',
              style: TextStyle(
                color: Colors.white,
                fontSize: compact ? 23 : 28,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Erp',
              style: TextStyle(
                color: const Color(0xFF8FD3C7),
                fontSize: compact ? 14 : 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _LoginCard extends StatelessWidget {
  const _LoginCard({
    required this.formKey,
    required this.selectedCompany,
    required this.usernameController,
    required this.passwordController,
    required this.passwordFocusNode,
    required this.isLoading,
    required this.onCompanyChanged,
    required this.onSubmit,
    required this.onClear,
  });

  final GlobalKey<FormState> formKey;
  final String selectedCompany;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final FocusNode passwordFocusNode;
  final bool isLoading;
  final ValueChanged<String?> onCompanyChanged;
  final Future<void> Function() onSubmit;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final companyValue = selectedCompany == 'Prosmart Erp'
        ? selectedCompany
        : 'Prosmart Erp';

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Giriş Yap',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Prosmart Erp hesabınızla devam edin.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              DropdownButtonFormField<String>(
                initialValue: companyValue,
                items: const [
                  DropdownMenuItem(
                    value: 'Prosmart Erp',
                    child: Text('Prosmart Erp'),
                  ),
                ],
                onChanged: isLoading ? null : onCompanyChanged,
                decoration: const InputDecoration(
                  labelText: 'Şirket',
                  prefixIcon: Icon(Icons.business_outlined),
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: usernameController,
                textInputAction: TextInputAction.next,
                enabled: !isLoading,
                autofillHints: const [AutofillHints.username],
                decoration: const InputDecoration(
                  labelText: 'Kullanıcı',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                onFieldSubmitted: (_) => passwordFocusNode.requestFocus(),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Kullanıcı adı gerekli';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: passwordController,
                focusNode: passwordFocusNode,
                textInputAction: TextInputAction.done,
                enabled: !isLoading,
                autofillHints: const [AutofillHints.password],
                decoration: const InputDecoration(
                  labelText: 'Şifre',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                obscureText: true,
                onFieldSubmitted: (_) => onSubmit(),
                validator: (value) {
                  if (AppConfig.hasApi && (value == null || value.isEmpty)) {
                    return 'Şifre giriniz';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: isLoading ? null : onSubmit,
                icon: isLoading
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login),
                label: const Text('Giriş'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: isLoading ? null : onClear,
                icon: const Icon(Icons.clear),
                label: const Text('Temizle'),
              ),
              if (!AppConfig.hasApi) ...[
                const SizedBox(height: 12),
                Text(
                  'Demo modunda şifre opsiyonel.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
