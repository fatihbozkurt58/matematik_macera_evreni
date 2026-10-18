import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  Future<AdultSession> signInWithApple();
  Future<void> sendVerification();
  Future<AdultSession?> refresh();
  Future<void> resetPassword(String email);
  Future<void> signOut();
}

abstract interface class AdultConsentStore {
  Future<bool> hasCurrentConsent();
  Future<void> acceptCurrentConsent();
}

class LocalAdultConsentStore implements AdultConsentStore {
  static const _key = 'adult_consent_version';
  static const _version = 'dev-adult-1';
  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  @override
  Future<bool> hasCurrentConsent() async =>
      await _prefs.getString(_key) == _version;

  @override
  Future<void> acceptCurrentConsent() => _prefs.setString(_key, _version);
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
  Future<AdultSession> signInWithApple() async {
    final provider = AppleAuthProvider()..addScope('email');
    // Firebase handles the native iOS nonce and Android OAuth redirect.
    // Sign in only: linking existing accounts requires reauthentication.
    final result = await _ready.signInWithProvider(provider);
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

enum AccessStep { credentials, verification, profilePending }

class AdultAccess extends StatefulWidget {
  const AdultAccess({super.key, required this.auth, this.consentStore});
  final AdultAuth auth;
  final AdultConsentStore? consentStore;

  @override
  State<AdultAccess> createState() => _AdultAccessState();
}

class _AdultAccessState extends State<AdultAccess> {
  AccessStep step = AccessStep.credentials;
  late final AdultConsentStore consentStore =
      widget.consentStore ?? LocalAdultConsentStore();
  bool bootstrapping = true;
  bool consentGranted = false;
  bool register = false;
  bool busy = false;
  bool obscure = true;
  bool initialized = false;
  String? error;
  AdultSession? session;
  final formKey = GlobalKey<FormState>();
  final email = TextEditingController();
  final password = TextEditingController();

  @override
  void initState() {
    super.initState();
    restoreSession();
  }

  Future<void> restoreSession() async {
    try {
      final accepted = await consentStore.hasCurrentConsent();
      if (!mounted) return;
      consentGranted = accepted;
      if (accepted) {
        final existing = await widget.auth.initialize();
        if (!mounted) return;
        initialized = true;
        if (existing != null) showSession(existing);
      }
    } catch (cause) {
      if (mounted) setState(() => error = explain(cause));
    } finally {
      if (mounted) setState(() => bootstrapping = false);
    }
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  String explain(Object cause) {
    if (cause is FirebaseAuthException) {
      return switch (cause.code) {
        'operation-not-allowed' => 'Bu giriş yöntemi henüz etkinleştirilmemiş. Başka bir yöntemle giriş yapın.',
        'web-context-canceled' ||
        'canceled' ||
        'cancelled' ||
        'popup-closed-by-user' =>
          'Giriş iptal edildi. Yeniden deneyebilirsiniz.',
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

  Future<bool> requestAdultConsent() async {
    var isAdult = false;
    var acceptsData = false;
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, updateSheet) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24,
            8,
            24,
            MediaQuery.viewInsetsOf(context).bottom + 24,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Yetişkin onayı',
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Hesap bir yetişkin tarafından yönetilir. Devam etmeden önce iki beyanı onaylayın.',
                  ),
                  const SizedBox(height: 16),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF5F7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(14),
                      child: Text(
                        'Bu geliştirme sürümünde hesap verileri dev Firebase projesine gönderilir. Gerçek çocuk bilgisi girmeyin.',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('18 yaşından büyük bir yetişkinim.'),
                    value: isAdult,
                    onChanged: (value) =>
                        updateSheet(() => isAdult = value ?? false),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text(
                      'Hesap verilerimin işlenmesini kabul ediyorum.',
                    ),
                    value: acceptsData,
                    onChanged: (value) =>
                        updateSheet(() => acceptsData = value ?? false),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: isAdult && acceptsData
                        ? () => Navigator.of(sheetContext).pop(true)
                        : null,
                    child: const Text('Onayla ve devam et'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(sheetContext).pop(false),
                    child: const Text('Vazgeç'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return accepted ?? false;
  }

  Future<bool> ensureReady() async {
    if (!consentGranted) {
      if (!await requestAdultConsent() || !mounted) return false;
      await consentStore.acceptCurrentConsent();
      consentGranted = true;
    }
    if (initialized) return true;
    try {
      final existing = await widget.auth.initialize();
      if (!mounted) return false;
      initialized = true;
      if (existing != null) showSession(existing);
      return existing == null;
    } catch (cause, stack) {
      if (kDebugMode) {
        debugPrint('Adult auth bootstrap failed: $cause');
        debugPrintStack(stackTrace: stack);
      }
      rethrow;
    }
  }

  Future<void> submit() async {
    if (!formKey.currentState!.validate()) return;
    await run(() async {
      if (!await ensureReady()) return;
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
    backgroundColor: const Color(0xFFF5FAFB),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Image.asset(
                    'assets/branding/splash-island.png',
                    width: 112,
                    height: 112,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Matematik Macerası',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF173C45),
                  ),
                ),
                const SizedBox(height: 30),
                Text(
                  switch (step) {
                    AccessStep.credentials => 'Yetişkin hesabı',
                    AccessStep.verification => 'E-postanızı doğrulayın',
                    AccessStep.profilePending => 'Hesabınız hazır',
                  },
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF172B3A),
                  ),
                ),
                const SizedBox(height: 16),
                if (bootstrapping) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 12),
                  const Text('Oturum kontrol ediliyor...'),
                ] else ...[
                  if (error != null) ...[
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFEEEE),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: Color(0xFFAE2626),
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: Text(error!)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (step == AccessStep.credentials) credentialsView(),
                  if (step == AccessStep.verification) verificationView(),
                  if (step == AccessStep.profilePending) pendingView(),
                  if (busy) ...[
                    const SizedBox(height: 18),
                    const LinearProgressIndicator(),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    ),
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
        const SizedBox(height: 22),
        TextFormField(
          controller: email,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
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
        const SizedBox(height: 18),
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
                    var sent = false;
                    await run(() async {
                      if (await ensureReady()) {
                        await widget.auth.resetPassword(value);
                        sent = true;
                      }
                    });
                    if (mounted && sent && error == null) {
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
        const SizedBox(height: 12),
        Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text('veya', style: Theme.of(context).textTheme.bodySmall),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: busy
              ? null
              : () => run(() async {
                  if (!await ensureReady()) return;
                  showSession(await widget.auth.signInWithGoogle());
                }),
          icon: const Icon(Icons.account_circle_outlined),
          label: const Text('Google ile devam et'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: busy
              ? null
              : () => run(() async {
                  if (!await ensureReady()) return;
                  showSession(await widget.auth.signInWithApple());
                }),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: Colors.black,
          ),
          icon: const Icon(Icons.apple),
          label: const Text('Apple ile devam et'),
        ),
        const SizedBox(height: 22),
        const Center(
          child: Text(
            'Hesap işlemleri yalnızca yetişkinler içindir.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF526773), fontSize: 13),
          ),
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
        'Giriş başarılı. Çocuk profili ve oyun haritası bu test sürümünde henüz açık değil.',
      ),
      const SizedBox(height: 20),
      OutlinedButton(
        onPressed: busy ? null : logout,
        child: const Text('Çıkış yap'),
      ),
    ],
  );
}
