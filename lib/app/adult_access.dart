import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'firebase_dev_bootstrap.dart';

class AdultSession {
  const AdultSession(this.uid, this.email, this.verified);
  final String uid;
  final String? email;
  final bool verified;
}

abstract interface class AdultAuth {
  Future<AdultSession?> initialize();
  Future<AdultSession> register(String email, String password);
  Future<AdultSession> signIn(String email, String password);
  Future<AdultSession> signInWithGoogle();
  Future<void> sendVerification();
  Future<AdultSession?> refresh();
  Future<void> resetPassword(String email);
  Future<void> signOut();
}

class FirebaseAdultAuth implements AdultAuth {
  FirebaseAuth? _auth;
  bool _googleInitialized = false;

  FirebaseAuth get _ready => _auth ?? (throw StateError('Consent required'));

  AdultSession _session(User user) =>
      AdultSession(user.uid, user.email, user.emailVerified);

  @override
  Future<AdultSession?> initialize() async {
    final app = await FirebaseDevBootstrap.initializeAfterAdultConsent();
    _auth = FirebaseAuth.instanceFor(app: app);
    final user = _ready.currentUser;
    if (user == null) return null;
    await user.reload();
    final refreshed = _ready.currentUser;
    return refreshed == null ? null : _session(refreshed);
  }

  @override
  Future<AdultSession> register(String email, String password) async {
    final result = await _ready.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    try {
      await result.user!.sendEmailVerification();
    } on FirebaseAuthException {
      // The account already exists; the verification screen can retry delivery.
    }
    return _session(result.user!);
  }

  @override
  Future<AdultSession> signIn(String email, String password) async {
    final result = await _ready.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    await result.user!.reload();
    return _session(_ready.currentUser!);
  }

  @override
  Future<AdultSession> signInWithGoogle() async {
    if (!_googleInitialized) {
      await GoogleSignIn.instance.initialize();
      _googleInitialized = true;
    }
    final account = await GoogleSignIn.instance.authenticate();
    final token = account.authentication.idToken;
    if (token == null) throw StateError('Google token missing');
    final result = await _ready.signInWithCredential(
      GoogleAuthProvider.credential(idToken: token),
    );
    return _session(result.user!);
  }

  @override
  Future<void> sendVerification() =>
      _ready.currentUser!.sendEmailVerification();

  @override
  Future<AdultSession?> refresh() async {
    final user = _ready.currentUser;
    if (user == null) return null;
    await user.reload();
    final refreshed = _ready.currentUser;
    return refreshed == null ? null : _session(refreshed);
  }

  @override
  Future<void> resetPassword(String email) =>
      _ready.sendPasswordResetEmail(email: email);

  @override
  Future<void> signOut() async {
    await _ready.signOut();
    if (_googleInitialized) await GoogleSignIn.instance.signOut();
  }
}

enum AccessStep { consent, loading, credentials, verification, profilePending }

class AdultAccess extends StatefulWidget {
  const AdultAccess({super.key, required this.auth});
  final AdultAuth auth;

  @override
  State<AdultAccess> createState() => _AdultAccessState();
}

class _AdultAccessState extends State<AdultAccess> {
  AccessStep step = AccessStep.consent;
  bool adult = false;
  bool necessary = false;
  bool register = false;
  bool busy = false;
  bool obscure = true;
  String? error;
  AdultSession? session;
  final formKey = GlobalKey<FormState>();
  final email = TextEditingController();
  final password = TextEditingController();

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  String explain(Object cause) {
    if (cause is FirebaseAuthException) {
      return switch (cause.code) {
        'email-already-in-use' => 'Bu e-posta için hesap bulunuyor.',
        'weak-password' => 'Daha güçlü bir şifre seçin.',
        'invalid-email' => 'Geçerli bir e-posta girin.',
        'network-request-failed' => 'Bağlantıyı kontrol edip yeniden deneyin.',
        'too-many-requests' => 'Çok fazla deneme. Bir süre sonra deneyin.',
        'account-exists-with-different-credential' =>
          'Bu e-posta başka bir yöntemle kayıtlı. Önce o yöntemle giriş yapın.',
        _ => 'İşlem tamamlanamadı. Bilgileri kontrol edip yeniden deneyin.',
      };
    }
    return 'İşlem tamamlanamadı. Bağlantıyı kontrol edip yeniden deneyin.';
  }

  Future<void> run(Future<void> Function() operation) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await operation();
    } catch (cause) {
      if (mounted) setState(() => error = explain(cause));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void showSession(AdultSession? value) {
    setState(() {
      session = value;
      if (value == null) register = false;
      step = value == null
          ? AccessStep.credentials
          : value.verified
          ? AccessStep.profilePending
          : AccessStep.verification;
      password.clear();
    });
  }

  Future<void> start() => run(() async {
    setState(() => step = AccessStep.loading);
    try {
      showSession(await widget.auth.initialize());
    } catch (cause, stack) {
      if (kDebugMode) {
        debugPrint('Adult auth bootstrap failed: $cause');
        debugPrintStack(stackTrace: stack);
      }
      if (mounted) setState(() => step = AccessStep.consent);
      rethrow;
    }
  });

  Future<void> submit() async {
    if (!formKey.currentState!.validate()) return;
    await run(() async {
      final value = register
          ? await widget.auth.register(email.text.trim(), password.text)
          : await widget.auth.signIn(email.text.trim(), password.text);
      showSession(value);
    });
  }

  Future<void> logout() => run(() async {
    await widget.auth.signOut();
    showSession(null);
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.asset(
                      'assets/branding/app-icon-master.png',
                      width: 88,
                      height: 88,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Matematik Macerası',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Yetişkin hesabı',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 32),
                if (step == AccessStep.consent) consentView(),
                if (step == AccessStep.loading)
                  const Center(child: CircularProgressIndicator()),
                if (step == AccessStep.credentials) credentialsView(),
                if (step == AccessStep.verification) verificationView(),
                if (step == AccessStep.profilePending) pendingView(),
                if (error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    error!,
                    style: const TextStyle(color: Color(0xFFAE2626)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget consentView() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Geliştirme sürümü. Yalnız test hesabı kullanın; gerçek çocuk bilgisi girmeyin.',
      ),
      const SizedBox(height: 16),
      const Text(
        'Devam edildiğinde hesap e-postası ve kimlik doğrulama verileri geliştirme Firebase projesine gönderilir. Çocuk profili ve oyun henüz kapalıdır.',
      ),
      const SizedBox(height: 16),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('18 yaşından büyük bir yetişkinim.'),
        value: adult,
        onChanged: busy ? null : (v) => setState(() => adult = v ?? false),
      ),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text(
          'Test hesabım için gerekli veri işlemesini kabul ediyorum.',
        ),
        value: necessary,
        onChanged: busy ? null : (v) => setState(() => necessary = v ?? false),
      ),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: adult && necessary && !busy ? start : null,
        child: const Text('Yetişkin hesabına geç'),
      ),
    ],
  );

  Widget credentialsView() => Form(
    key: formKey,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Giriş')),
            ButtonSegment(value: true, label: Text('Kayıt')),
          ],
          selected: {register},
          onSelectionChanged: busy
              ? null
              : (v) => setState(() {
                  register = v.first;
                  error = null;
                }),
        ),
        const SizedBox(height: 24),
        TextFormField(
          controller: email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(labelText: 'E-posta'),
          validator: (v) =>
              v != null &&
                  RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v.trim())
              ? null
              : 'Geçerli bir e-posta girin.',
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: password,
          obscureText: obscure,
          autofillHints: [
            register ? AutofillHints.newPassword : AutofillHints.password,
          ],
          decoration: InputDecoration(
            labelText: 'Şifre',
            suffixIcon: IconButton(
              tooltip: obscure ? 'Şifreyi göster' : 'Şifreyi gizle',
              icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => obscure = !obscure),
            ),
          ),
          validator: (v) {
            if (v == null || v.isEmpty) return 'Şifre girin.';
            if (register &&
                (v.length < 10 ||
                    !RegExp(r'[A-Za-z]').hasMatch(v) ||
                    !RegExp(r'[0-9]').hasMatch(v))) {
              return 'En az 10 karakter, bir harf ve bir rakam kullanın.';
            }
            return null;
          },
          onFieldSubmitted: (_) {
            if (!busy) submit();
          },
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: busy ? null : submit,
          child: Text(register ? 'Hesap oluştur' : 'Giriş yap'),
        ),
        if (!register)
          TextButton(
            onPressed: busy
                ? null
                : () async {
                    final value = email.text.trim();
                    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                        .hasMatch(value)) {
                      setState(() => error = 'Önce geçerli bir e-posta girin.');
                      return;
                    }
                    await run(() => widget.auth.resetPassword(value));
                    if (mounted && error == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Hesap varsa sıfırlama bağlantısı gönderildi.',
                          ),
                        ),
                      );
                    }
                  },
            child: const Text('Şifremi unuttum'),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: busy
              ? null
              : () => run(() async {
                  showSession(await widget.auth.signInWithGoogle());
                }),
          icon: const Icon(Icons.account_circle_outlined),
          label: const Text('Google ile devam et'),
        ),
      ],
    ),
  );

  Widget verificationView() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        '${session?.email ?? 'E-posta adresinizi'} doğrulayın. Bağlantı gelmediyse yeniden gönderin.',
      ),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: busy
            ? null
            : () => run(() async {
                showSession(await widget.auth.refresh());
              }),
        child: const Text('Doğrulamayı kontrol et'),
      ),
      TextButton(
        onPressed: busy ? null : () => run(widget.auth.sendVerification),
        child: const Text('Bağlantıyı yeniden gönder'),
      ),
      TextButton(
        onPressed: busy ? null : logout,
        child: const Text('Çıkış yap'),
      ),
    ],
  );

  Widget pendingView() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Icon(
        Icons.verified_user_outlined,
        size: 52,
        color: Color(0xFF137C72),
      ),
      const SizedBox(height: 16),
      const Text(
        'Hesap doğrulandı. Öğrenci profili ve ilerleme bağlantısı bu geliştirme sürümünde henüz açılmadı.',
      ),
      const SizedBox(height: 8),
      Text(
        'Hesap kimliği: ${session?.uid ?? ''}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      const SizedBox(height: 20),
      OutlinedButton(
        onPressed: busy ? null : logout,
        child: const Text('Çıkış yap'),
      ),
    ],
  );
}
