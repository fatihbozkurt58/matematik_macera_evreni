import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show appFlavor;
import 'package:google_sign_in/google_sign_in.dart';

import 'firebase_dev_bootstrap.dart';
import 'student_profile.dart';

const devTestAccountsEnabled =
    kDebugMode &&
    bool.fromEnvironment('ENABLE_DEV_TEST_ACCOUNTS', defaultValue: false);

class StudentSession {
  const StudentSession(this.uid, this.email, this.verified, {this.nickname});
  final String uid;
  final String? email;
  final bool verified;
  final String? nickname;
}

abstract interface class StudentAuth {
  Stream<StudentSession?> get sessionChanges;
  Future<StudentSession?> initialize();
  Future<StudentSession> register(
    String nickname,
    String email,
    String password,
  );
  Future<StudentSession> signIn(String email, String password);
  Future<StudentSession> signInWithGoogle();
  Future<StudentSession> signInWithApple();
  Future<void> sendVerification();
  Future<StudentSession?> refresh();
  Future<void> resetPassword(String email);
  Future<void> signOut();
}

class FirebaseStudentAuth implements StudentAuth {
  FirebaseAuth? _auth;
  bool _googleInitialized = false;

  FirebaseAuth get _ready =>
      _auth ?? (throw StateError('Firebase is not initialized'));

  @override
  Stream<StudentSession?> get sessionChanges => _ready.idTokenChanges().map(
    (user) => user == null ? null : _session(user),
  );

  StudentSession _session(User user) => StudentSession(
    user.uid,
    user.email,
    user.emailVerified,
    nickname:
        user.providerData.any((provider) => provider.providerId == 'password')
        ? user.displayName
        : null,
  );

  void _requireDevTestAccounts() {
    if (!devTestAccountsEnabled || appFlavor != 'dev') {
      throw StateError('New accounts are not enabled for this build.');
    }
  }

  @override
  Future<StudentSession?> initialize() async {
    final app = await FirebaseDevBootstrap.initialize();
    _auth = FirebaseAuth.instanceFor(app: app);
    final user = _ready.currentUser;
    if (user == null) return null;
    await user.reload();
    final refreshed = _ready.currentUser;
    return refreshed == null ? null : _session(refreshed);
  }

  @override
  Future<StudentSession> signIn(String email, String password) async {
    final result = await _ready.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    await result.user!.reload();
    return _session(_ready.currentUser!);
  }

  @override
  Future<StudentSession> register(
    String nickname,
    String email,
    String password,
  ) async {
    _requireDevTestAccounts();
    final result = await _ready.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    await result.user!.updateDisplayName(nickname);
    await result.user!.sendEmailVerification();
    return _session(result.user!);
  }

  @override
  Future<StudentSession> signInWithGoogle() async {
    _requireDevTestAccounts();
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
  Future<StudentSession> signInWithApple() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      throw UnsupportedError('Apple sign-in is available only on iOS.');
    }
    _requireDevTestAccounts();
    final provider = AppleAuthProvider()..addScope('email');
    // Firebase handles the native iOS nonce.
    // Sign in only: linking existing accounts requires reauthentication.
    final result = await _ready.signInWithProvider(provider);
    return _session(result.user!);
  }

  @override
  Future<void> sendVerification() =>
      _ready.currentUser!.sendEmailVerification();

  @override
  Future<StudentSession?> refresh() async {
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

enum AccessStep {
  credentials,
  verification,
  profileForm,
  compliancePending,
  ready,
  profileError,
}

class StudentAccess extends StatefulWidget {
  const StudentAccess({
    super.key,
    required this.auth,
    required this.profiles,
    this.allowDevTestAccounts = false,
  });
  final StudentAuth auth;
  final StudentProfileRepository profiles;
  final bool allowDevTestAccounts;

  @override
  State<StudentAccess> createState() => _StudentAccessState();
}

class _StudentAccessState extends State<StudentAccess>
    with WidgetsBindingObserver {
  AccessStep step = AccessStep.credentials;
  bool bootstrapping = true;
  bool busy = false;
  bool obscure = true;
  bool initialized = false;
  bool register = false;
  bool profileLoading = false;
  int? grade;
  String? error;
  StudentSession? session;
  StudentProfile? profile;
  final formKey = GlobalKey<FormState>();
  final profileFormKey = GlobalKey<FormState>();
  final nickname = TextEditingController();
  final profileNickname = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  final passwordRepeat = TextEditingController();
  StreamSubscription<StudentSession?>? sessionSubscription;

  void watchAuthChanges() {
    sessionSubscription ??= widget.auth.sessionChanges.listen((changed) {
      if (!mounted || bootstrapping || busy) return;
      if (changed?.uid != session?.uid ||
          changed?.verified != session?.verified) {
        unawaited(showSession(changed));
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    restoreSession();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed ||
        !initialized ||
        session == null ||
        busy ||
        bootstrapping) {
      return;
    }
    unawaited(run(() async => showSession(await widget.auth.refresh())));
  }

  Future<void> restoreSession() async {
    try {
      final existing = await widget.auth.initialize();
      if (!mounted) return;
      initialized = true;
      if (existing != null) await showSession(existing);
      watchAuthChanges();
    } catch (cause) {
      if (mounted) setState(() => error = explain(cause));
    } finally {
      if (mounted) setState(() => bootstrapping = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final subscription = sessionSubscription;
    if (subscription != null) unawaited(subscription.cancel());
    nickname.dispose();
    profileNickname.dispose();
    email.dispose();
    password.dispose();
    passwordRepeat.dispose();
    super.dispose();
  }

  String explain(Object cause) {
    if (cause is FirebaseFunctionsException) {
      return switch (cause.code) {
        'failed-precondition' => 'Önce e-posta doğrulamasını tamamlayın.',
        'already-exists' => 'Bu hesap için profil zaten var. Yeniden yükleyin.',
        'unavailable' =>
          'Sunucuya ulaşılamadı. Bağlantıyı kontrol edip yeniden deneyin.',
        _ => 'Profil kaydedilemedi. Biraz sonra yeniden deneyin.',
      };
    }
    if (cause is FirebaseException && cause.plugin == 'cloud_firestore') {
      return 'Profil okunamadı. Bağlantıyı kontrol edip yeniden deneyin.';
    }
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

  Future<void> showSession(StudentSession? value) async {
    if (!mounted) return;
    setState(() {
      session = value;
      if (value == null) register = false;
      profile = null;
      profileLoading = value?.verified ?? false;
      step = value == null
          ? AccessStep.credentials
          : value.verified
          ? AccessStep.profileForm
          : AccessStep.verification;
      if (value?.nickname != null) profileNickname.text = value!.nickname!;
      password.clear();
      passwordRepeat.clear();
    });
    if (value == null || !value.verified) return;
    try {
      final loaded = await widget.profiles.load(value.uid);
      if (!mounted || session?.uid != value.uid) return;
      setState(() {
        profile = loaded;
        step = loaded == null
            ? AccessStep.profileForm
            : loaded.canEnterGame
            ? AccessStep.ready
            : AccessStep.compliancePending;
      });
    } catch (cause) {
      if (mounted && session?.uid == value.uid) {
        setState(() {
          error = explain(cause);
          step = AccessStep.profileError;
        });
      }
    } finally {
      if (mounted && session?.uid == value.uid) {
        setState(() => profileLoading = false);
      }
    }
  }

  Future<bool> ensureReady() async {
    if (initialized) return true;
    try {
      final existing = await widget.auth.initialize();
      if (!mounted) return false;
      initialized = true;
      if (existing != null) await showSession(existing);
      watchAuthChanges();
      return existing == null;
    } catch (cause, stack) {
      if (kDebugMode) {
        debugPrint('Student auth bootstrap failed: $cause');
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
          ? await widget.auth.register(
              nickname.text.trim(),
              email.text.trim(),
              password.text,
            )
          : await widget.auth.signIn(email.text.trim(), password.text);
      await showSession(value);
    });
  }

  Future<void> logout() => run(() async {
    await widget.auth.signOut();
    await showSession(null);
  });

  Future<void> submitProfile() async {
    if (!profileFormKey.currentState!.validate()) return;
    await run(() async {
      final uid = session?.uid;
      if (uid == null || session?.verified != true) return;
      final saved = await widget.profiles.complete(
        uid,
        profileNickname.text.trim(),
        grade!,
      );
      if (!mounted || session?.uid != uid) return;
      setState(() {
        profile = saved;
        step = saved.canEnterGame
            ? AccessStep.ready
            : AccessStep.compliancePending;
      });
    });
  }

  bool _validNickname(String? value) {
    final name = value?.trim() ?? '';
    return RegExp(r'^[a-zA-ZÇĞİÖŞÜçğıöşü][a-zA-ZÇĞİÖŞÜçğıöşü0-9_]{2,19}$')
        .hasMatch(name);
  }

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
                    AccessStep.credentials => 'Hoş geldin',
                    AccessStep.verification => 'E-postanızı doğrulayın',
                    AccessStep.profileForm => 'Profilini tamamla',
                    AccessStep.compliancePending => 'Hesap hazırlanıyor',
                    AccessStep.ready => 'Hazırsın',
                    AccessStep.profileError => 'Profil yüklenemedi',
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
                  if (step == AccessStep.profileForm && !profileLoading)
                    profileFormView(),
                  if (step == AccessStep.compliancePending)
                    compliancePendingView(),
                  if (step == AccessStep.ready) readyView(),
                  if (step == AccessStep.profileError) profileErrorView(),
                  if (busy || profileLoading) ...[
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
        if (widget.allowDevTestAccounts) ...[
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Giriş')),
              ButtonSegment(value: true, label: Text('Kayıt')),
            ],
            selected: {register},
            onSelectionChanged: busy
                ? null
                : (value) => setState(() {
                    register = value.first;
                    error = null;
                    passwordRepeat.clear();
                  }),
          ),
          const SizedBox(height: 18),
        ],
        if (!widget.allowDevTestAccounts) const SizedBox(height: 18),
        if (register) ...[
          TextFormField(
            controller: nickname,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Takma Adınız'),
            validator: (value) => _validNickname(value)
                ? null
                : '3-20 karakterlik bir takma ad girin.',
          ),
          const SizedBox(height: 12),
        ],
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
        if (register) ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: passwordRepeat,
            obscureText: obscure,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.newPassword],
            decoration: const InputDecoration(labelText: 'Şifre tekrar'),
            validator: (value) =>
                value == password.text ? null : 'Şifreler eşleşmiyor.',
            onFieldSubmitted: (_) {
              if (!busy) submit();
            },
          ),
        ],
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
          onPressed: busy || !widget.allowDevTestAccounts
              ? null
              : () => run(() async {
                  if (!await ensureReady()) return;
                  await showSession(await widget.auth.signInWithGoogle());
                }),
          icon: const Icon(Icons.account_circle_outlined),
          label: const Text('Google ile devam et'),
        ),
        if (Theme.of(context).platform == TargetPlatform.iOS) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: busy || !widget.allowDevTestAccounts
                ? null
                : () => run(() async {
                    if (!await ensureReady()) return;
                    await showSession(await widget.auth.signInWithApple());
                  }),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.black,
            ),
            icon: const Icon(Icons.apple),
            label: const Text('Apple ile devam et'),
          ),
        ],
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
                await showSession(await widget.auth.refresh());
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

  Widget profileFormView() => Form(
    key: profileFormKey,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: profileNickname,
          decoration: const InputDecoration(labelText: 'Takma Adınız'),
          validator: (value) => _validNickname(value)
              ? null
              : '3-20 karakterlik bir takma ad girin.',
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: grade,
          decoration: const InputDecoration(labelText: 'Sınıfın'),
          items: [
            for (var value = 1; value <= 5; value++)
              DropdownMenuItem(value: value, child: Text('$value. sınıf')),
          ],
          onChanged: busy ? null : (value) => setState(() => grade = value),
          validator: (value) => value == null ? 'Sınıfını seç.' : null,
        ),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: busy ? null : submitProfile,
          child: const Text('Profili kaydet'),
        ),
        TextButton(
          onPressed: busy ? null : logout,
          child: const Text('Çıkış yap'),
        ),
      ],
    ),
  );

  Widget compliancePendingView() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Icon(Icons.shield_outlined, size: 52, color: Color(0xFF137C72)),
      const SizedBox(height: 16),
      const Text(
        'Profilin kaydedildi. Hesap uygunluğu tamamlanana kadar oyun alanı kapalı.',
      ),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: busy ? null : () => run(() => showSession(session)),
        child: const Text('Durumu kontrol et'),
      ),
      OutlinedButton(
        onPressed: busy ? null : logout,
        child: const Text('Çıkış yap'),
      ),
    ],
  );

  Widget profileErrorView() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FilledButton(
        onPressed: busy ? null : () => run(() => showSession(session)),
        child: const Text('Yeniden dene'),
      ),
      TextButton(
        onPressed: busy ? null : logout,
        child: const Text('Çıkış yap'),
      ),
    ],
  );

  Widget readyView() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('${profile?.nickname ?? ''} · ${profile?.grade ?? ''}. sınıf'),
      const SizedBox(height: 12),
      const Text('Oyun alanı sonraki aşamada açılacak.'),
      TextButton(
        onPressed: busy ? null : logout,
        child: const Text('Çıkış yap'),
      ),
    ],
  );
}
