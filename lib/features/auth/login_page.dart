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
  String _selectedCompany = 'NBOS';

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);

    ref.listen(authControllerProvider, (_, next) {
      if (next.hasError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.error.toString())),
        );
      }
      if (next.asData?.value != null) {
        context.go('/');
      }
    });

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'NBOS/images/pic/welcomedolu.png',
              fit: BoxFit.cover,
            ),
          ),
          Center(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                image: DecorationImage(
                  image: AssetImage('NBOS/images/pic/login_back.gif'),
                  fit: BoxFit.fill,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(26, 18, 26, 18),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.only(bottom: 6),
                          decoration: const BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: Colors.white24),
                            ),
                          ),
                          child: const Text(
                            'Kullanıcı Girişi',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Table(
                          columnWidths: const {
                            0: IntrinsicColumnWidth(),
                            1: FixedColumnWidth(190),
                          },
                          defaultVerticalAlignment:
                              TableCellVerticalAlignment.middle,
                          children: [
                            TableRow(
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(right: 10, bottom: 8),
                                  child: Text(
                                    'Şirket',
                                    style: TextStyle(color: Colors.white, fontSize: 12),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: DropdownButtonFormField<String>(
                                    initialValue: _selectedCompany,
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'NBOS',
                                        child: Text('NBOS'),
                                      ),
                                    ],
                                    onChanged: auth.isLoading
                                        ? null
                                        : (v) => setState(
                                              () => _selectedCompany = v ?? 'NBOS',
                                            ),
                                    decoration: const InputDecoration(isDense: true),
                                  ),
                                ),
                              ],
                            ),
                            TableRow(
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(right: 10, bottom: 8),
                                  child: Text(
                                    'Kullanıcı',
                                    style: TextStyle(color: Colors.white, fontSize: 12),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: TextFormField(
                                    controller: _usernameController,
                                    decoration: const InputDecoration(isDense: true),
                                    validator: (v) {
                                      if (v == null || v.trim().isEmpty) {
                                        return 'Kullanıcı adı gerekli';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                              ],
                            ),
                            TableRow(
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(right: 10),
                                  child: Text(
                                    'Şifre',
                                    style: TextStyle(color: Colors.white, fontSize: 12),
                                  ),
                                ),
                                TextFormField(
                                  controller: _passwordController,
                                  decoration: const InputDecoration(isDense: true),
                                  obscureText: true,
                                  validator: (_) => null,
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 78,
                              child: OutlinedButton(
                                onPressed: auth.isLoading
                                    ? null
                                    : () async {
                                        if (!_formKey.currentState!.validate()) return;
                                        await ref
                                            .read(authControllerProvider.notifier)
                                            .login(
                                              username: _usernameController.text,
                                              password: _passwordController.text,
                                            );
                                      },
                                child: auth.isLoading
                                    ? const SizedBox(
                                        height: 16,
                                        width: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Text('Giriş'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 78,
                              child: OutlinedButton(
                                onPressed: auth.isLoading
                                    ? null
                                    : () {
                                        _usernameController.clear();
                                        _passwordController.clear();
                                        setState(() {});
                                      },
                                child: const Text('İptal'),
                              ),
                            ),
                          ],
                        ),
                        if (!AppConfig.hasApi) const SizedBox(height: 6),
                        if (!AppConfig.hasApi)
                          Text(
                            'Demo modunda şifre opsiyonel.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white, fontSize: 11),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
