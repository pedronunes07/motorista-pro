import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'main.dart' show HomeScreen;

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
        stream: FirebaseAuth.instance.userChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          final user = snapshot.data;
          if (user == null) return const LoginScreen();
          if (user.email != null && !user.emailVerified) return const VerifyEmailScreen();
          return const HomeScreen();
        },
      );
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  final phone = TextEditingController(text: '+55');
  final code = TextEditingController();
  bool useSms = false;
  bool createAccount = false;
  bool loading = false;
  String? verificationId;
  String? message;

  @override
  void dispose() {
    email.dispose(); password.dispose(); phone.dispose(); code.dispose();
    super.dispose();
  }

  void _error(Object error) {
    final text = error is FirebaseAuthException ? _friendlyError(error) : 'Não foi possível continuar. Tente novamente.';
    if (mounted) setState(() { loading = false; message = text; });
  }

  Future<void> _emailSubmit() async {
    FocusScope.of(context).unfocus();
    setState(() { loading = true; message = null; });
    try {
      if (createAccount) {
        final result = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email.text.trim(), password: password.text);
        await result.user?.sendEmailVerification();
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(email: email.text.trim(), password: password.text);
      }
      if (mounted) setState(() => loading = false);
    } catch (error) { _error(error); }
  }

  Future<void> _sendSms() async {
    FocusScope.of(context).unfocus();
    setState(() { loading = true; message = null; });
    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: phone.text.replaceAll(RegExp(r'[^+\d]'), ''),
      verificationCompleted: (credential) async => FirebaseAuth.instance.signInWithCredential(credential),
      verificationFailed: _error,
      codeSent: (id, _) {
        if (mounted) setState(() { verificationId = id; loading = false; message = 'Código enviado por SMS.'; });
      },
      codeAutoRetrievalTimeout: (id) { verificationId = id; if (mounted) setState(() => loading = false); },
    );
  }

  Future<void> _confirmSms() async {
    if (verificationId == null) return;
    setState(() { loading = true; message = null; });
    try {
      final credential = PhoneAuthProvider.credential(verificationId: verificationId!, smsCode: code.text.trim());
      await FirebaseAuth.instance.signInWithCredential(credential);
    } catch (error) { _error(error); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const Icon(Icons.local_taxi, size: 56, color: Color(0xFF155EEF)),
                      const SizedBox(height: 12),
                      Text('Motorista Pro', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      const Text('Entre para acessar seus dados e a calculadora.', textAlign: TextAlign.center),
                      const SizedBox(height: 24),
                      const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.email_outlined), SizedBox(width: 8), Text('Acesso por e-mail')]),
                      const SizedBox(height: 20),
                      if (!useSms) ...[
                        TextField(controller: email, keyboardType: TextInputType.emailAddress, autocorrect: false, decoration: const InputDecoration(labelText: 'E-mail', border: OutlineInputBorder())),
                        const SizedBox(height: 12),
                        TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Senha (mínimo 6 caracteres)', border: OutlineInputBorder())),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: loading ? null : _emailSubmit, child: Text(createAccount ? 'Criar conta e verificar e-mail' : 'Entrar')),
                        TextButton(onPressed: loading ? null : () => setState(() { createAccount = !createAccount; message = null; }), child: Text(createAccount ? 'Já tenho uma conta' : 'Criar uma conta')),
                      ] else ...[
                        TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Celular com DDD', hintText: '+55 21 99999-9999', border: OutlineInputBorder())),
                        if (verificationId != null) ...[const SizedBox(height: 12), TextField(controller: code, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Código recebido', border: OutlineInputBorder()))],
                        const SizedBox(height: 16),
                        FilledButton(onPressed: loading ? null : (verificationId == null ? _sendSms : _confirmSms), child: Text(verificationId == null ? 'Enviar código por SMS' : 'Confirmar código')),
                        if (verificationId != null) TextButton(onPressed: loading ? null : () => setState(() { verificationId = null; code.clear(); }), child: const Text('Trocar número')),
                      ],
                      if (loading) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
                      if (message != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(message!, textAlign: TextAlign.center, style: TextStyle(color: message!.startsWith('Código') ? Colors.green : Colors.red))),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});
  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  bool loading = false;
  String? message;

  Future<void> _check() async {
    setState(() { loading = true; message = null; });
    await FirebaseAuth.instance.currentUser?.reload();
    final verified = FirebaseAuth.instance.currentUser?.emailVerified ?? false;
    if (!verified && mounted) setState(() { loading = false; message = 'O e-mail ainda não foi confirmado.'; });
    if (verified) await FirebaseAuth.instance.currentUser?.getIdToken(true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(body: SafeArea(child: Center(child: Padding(padding: const EdgeInsets.all(28), child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.mark_email_unread_outlined, size: 72, color: Color(0xFF155EEF)),
    const SizedBox(height: 20),
    Text('Confirme seu e-mail', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
    const SizedBox(height: 10),
    Text('Enviamos uma mensagem para ${FirebaseAuth.instance.currentUser?.email}. Abra o link recebido e volte aqui.' , textAlign: TextAlign.center),
    const SizedBox(height: 22),
    SizedBox(width: double.infinity, child: FilledButton(onPressed: loading ? null : _check, child: const Text('Já confirmei'))),
    TextButton(onPressed: () async { await FirebaseAuth.instance.currentUser?.sendEmailVerification(); if (mounted) setState(() => message = 'Novo e-mail de confirmação enviado.'); }, child: const Text('Reenviar e-mail')),
    TextButton(onPressed: () => FirebaseAuth.instance.signOut(), child: const Text('Usar outra conta')),
    if (loading) const CircularProgressIndicator(),
    if (message != null) Text(message!, textAlign: TextAlign.center),
  ]))))));
}

String _friendlyError(FirebaseAuthException error) {
  switch (error.code) {
    case 'invalid-email': return 'Digite um e-mail válido.';
    case 'weak-password': return 'A senha precisa ter pelo menos 6 caracteres.';
    case 'email-already-in-use': return 'Este e-mail já possui uma conta.';
    case 'invalid-credential': case 'wrong-password': case 'user-not-found': return 'E-mail ou senha incorretos.';
    case 'invalid-phone-number': return 'Digite o celular com +55 e DDD.';
    case 'invalid-verification-code': return 'O código SMS está incorreto.';
    case 'too-many-requests': return 'Muitas tentativas. Aguarde alguns minutos.';
    case 'operation-not-allowed': return 'Este tipo de login ainda precisa ser ativado no Firebase.';
    default: return error.message ?? 'Não foi possível entrar.';
  }
}
