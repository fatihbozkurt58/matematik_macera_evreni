import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show appFlavor;
import 'package:google_sign_in/google_sign_in.dart';

import 'firebase_dev_bootstrap.dart';
import 'student_profile.dart';
import 'session_preference.dart';
import 'adventure_home.dart';

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
  bool get staySignedIn;
  Future<void> setStaySignedIn(bool value);
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
  FirebaseStudentAuth({SessionPreference? preference})
    : _preference = preference ?? SecureSessionPreference();

  final SessionPreference _preference;
  bool _policyApplied = false;
  @override
  bool staySignedIn = true;

  @override
  Future<void> setStaySignedIn(bool value) async {
    await _preference.write(value);
    staySignedIn = value;
  }

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
    if (!_policyApplied) {
      staySignedIn = await _preference.read();
      if (!staySignedIn) await _ready.signOut();
      _policyApplied = true;
    }
    return refresh();
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
    try {
      await user.reload();
      // A refresh token may have been revoked without an Auth state event.
      await _ready.currentUser?.getIdToken(true);
      final refreshed = _ready.currentUser;
      return refreshed == null ? null : _session(refreshed);
    } on FirebaseAuthException catch (error) {
      if (invalidSessionCodes.contains(error.code) &&
          _ready.currentUser?.uid == user.uid) {
        await _ready.signOut();
      }
      rethrow;
    }
  }

  @override
  Future<void> resetPassword(String email) async {
    try {
      await _ready.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (error) {
      if (error.code != 'user-not-found') rethrow;
      // An unknown email has the same visible result as an existing account.
    }
  }

  @override
  Future<void> signOut() async {
    await _ready.signOut();
    if (_googleInitialized) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {
        // Firebase sign-out is authoritative; provider chooser cleanup can retry.
      }
    }
  }
}

const invalidSessionCodes = {
  'user-disabled',
  'user-not-found',
  'user-token-expired',
  'invalid-user-token',
  'id-token-revoked',
};

enum AccessStep {
  credentials,
  verification,
  profileForm,
  compliancePending,
  ready,
  profileError,
  accountBlocked,
  sessionError,
}

class StudentAccess extends StatefulWidget {
  const StudentAccess({
    super.key,
    required this.auth,
    required this.profiles,
    this.allowDevTestAccounts = false,
    this.requestTimeout = const Duration(seconds: 20),
  });
  final StudentAuth auth;
  final StudentProfileRepository profiles;
  final bool allowDevTestAccounts;
  final Duration requestTimeout;

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
  bool staySignedIn = true;
  int sessionEpoch = 0;
  int profileRequest = 0;
  int? grade;
  String? error;
  StudentSession? session;
  StudentProfile? profile;
  final signInFormKey = GlobalKey<FormState>();
  final registrationFormKey = GlobalKey<FormState>();
  GlobalKey<FormState> get formKey =>
      register ? registrationFormKey : signInFormKey;
  final profileFormKey = GlobalKey<FormState>();
  final nickname = TextEditingController();
  final profileNickname = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  final passwordRepeat = TextEditingController();
  StreamSubscription<StudentSession?>? sessionSubscription;
  StreamSubscription<StudentProfile?>? profileSubscription;

  void watchAuthChanges() {
    sessionSubscription ??= widget.auth.sessionChanges.listen(
      (changed) {
        if (!mounted) return;
        if (changed?.uid != session?.uid ||
            changed?.verified != session?.verified) {
          unawaited(showSession(changed));
        }
      },
      onError: (Object cause) {
        if (mounted) unawaited(handleFailure(cause));
      },
    );
  }

  void watchProfile(String uid, int request) {
    profileSubscription = widget.profiles
        .watch(uid)
        .listen(
          (loaded) {
            if (!mounted || session?.uid != uid || profileRequest != request) {
              return;
            }
            if (loaded != null && loaded.uid != uid) {
              setState(() {
                profile = null;
                step = AccessStep.profileError;
              });
              return;
            }
            setState(() {
              profile = loaded;
              step = loaded == null
                  ? AccessStep.profileForm
                  : loaded.isBlocked
                  ? AccessStep.accountBlocked
                  : loaded.canOpenHome
                  ? AccessStep.ready
                  : AccessStep.compliancePending;
            });
          },
          onError: (Object cause) {
            if (!mounted || session?.uid != uid || profileRequest != request) {
              return;
            }
            setState(() {
              profile = null;
              step = AccessStep.profileError;
              error = explain(cause);
            });
          },
        );
  }

  Future<void> handleFailure(Object cause) async {
    if (cause is FirebaseAuthException &&
        invalidSessionCodes.contains(cause.code)) {
      await showSession(null);
    }
    if (mounted) setState(() => error = explain(cause));
  }

  Future<void> applyAuthResult(StudentSession? value, int epoch) async {
    if (!mounted) return;
    if (sessionEpoch != epoch && (value == null || session?.uid != value.uid)) {
      return;
    }
    await showSession(value);
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
    unawaited(refreshSession());
  }

  Future<void> refreshSession() => run(() async {
    final epoch = sessionEpoch;
    try {
      final refreshed = await widget.auth.refresh().timeout(
        widget.requestTimeout,
      );
      await applyAuthResult(refreshed, epoch);
    } catch (cause) {
      if (!mounted || epoch != sessionEpoch) return;
      if (mounted && epoch == sessionEpoch) {
        setState(() {
          profileRequest++;
          final subscription = profileSubscription;
          profileSubscription = null;
          if (subscription != null) unawaited(subscription.cancel());
          profile = null;
          step = AccessStep.sessionError;
        });
      }
      rethrow;
    }
  });

  Future<void> restoreSession() async {
    if (mounted) {
      setState(() {
        bootstrapping = true;
        error = null;
      });
    }
    try {
      final existing = await widget.auth.initialize().timeout(
        widget.requestTimeout,
      );
      if (!mounted) return;
      initialized = true;
      staySignedIn = widget.auth.staySignedIn;
      watchAuthChanges();
      if (existing != null) await showSession(existing);
    } catch (cause) {
      if (mounted) await handleFailure(cause);
    } finally {
      if (mounted) setState(() => bootstrapping = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final subscription = sessionSubscription;
    if (subscription != null) unawaited(subscription.cancel());
    final profileWatch = profileSubscription;
    if (profileWatch != null) unawaited(profileWatch.cancel());
    nickname.dispose();
    profileNickname.dispose();
    email.dispose();
    password.dispose();
    passwordRepeat.dispose();
    super.dispose();
  }

  String explain(Object cause) {
    if (cause is TimeoutException) {
      return 'İşlem zaman aşımına uğradı. Yeniden deneyin.';
    }
    if (cause is GoogleSignInException &&
        cause.code == GoogleSignInExceptionCode.canceled) {
      return 'Giriş iptal edildi. Yeniden deneyebilirsiniz.';
    }
    if (cause is FirebaseFunctionsException) {
      return switch (cause.code) {
        'unauthenticated' =>
          'Güvenli bağlantı doğrulanamadı. Uygulamayı yeniden açıp deneyin.',
        'resource-exhausted' => 'Çok fazla deneme. Bir süre sonra deneyin.',
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
        'user-disabled' ||
        'user-not-found' ||
        'user-token-expired' ||
        'invalid-user-token' ||
        'id-token-revoked' =>
          'Oturum sona erdi. Devam etmek için yeniden giriş yapın.',
        'operation-not-allowed' => 'Bu giriş yöntemi henüz etkinleştirilmemiş. Başka bir yöntemle giriş yapın.',
        'web-context-canceled' ||
        'canceled' ||
        'cancelled' ||
        'popup-closed-by-user' =>
          'Giriş iptal edildi. Yeniden deneyebilirsiniz.',
        'email-already-in-use' => 'Kayıt tamamlanamadı. Giriş yapmayı veya şifreni sıfırlamayı deneyebilirsin.',
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
      if (mounted) await handleFailure(cause);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> showSession(StudentSession? value) async {
    if (!mounted) return;
    final request = ++profileRequest;
    final previousWatch = profileSubscription;
    profileSubscription = null;
    if (previousWatch != null) unawaited(previousWatch.cancel());
    sessionEpoch++;
    setState(() {
      if (session?.uid != value?.uid) {
        grade = null;
        profileNickname.clear();
        if (session != null) {
          email.clear();
          nickname.clear();
        }
      }
      error = null;
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
      final loaded = await widget.profiles
          .load(value.uid)
          .timeout(widget.requestTimeout);
      if (!mounted || session?.uid != value.uid || request != profileRequest) {
        return;
      }
      if (loaded != null && loaded.uid != value.uid) {
        throw StateError('PROFILE_UID_MISMATCH');
      }
      setState(() {
        profile = loaded;
        step = loaded == null
            ? AccessStep.profileForm
            : loaded.isBlocked
            ? AccessStep.accountBlocked
            : loaded.canOpenHome
            ? AccessStep.ready
            : AccessStep.compliancePending;
      });
      watchProfile(value.uid, request);
    } catch (cause) {
      if (mounted && session?.uid == value.uid && request == profileRequest) {
        setState(() {
          error = explain(cause);
          step = AccessStep.profileError;
        });
      }
    } finally {
      if (mounted && session?.uid == value.uid && request == profileRequest) {
        setState(() => profileLoading = false);
      }
    }
  }

  Future<bool> ensureReady() async {
    if (initialized) return true;
    try {
      final existing = await widget.auth.initialize().timeout(
        widget.requestTimeout,
      );
      if (!mounted) return false;
      initialized = true;
      staySignedIn = widget.auth.staySignedIn;
      watchAuthChanges();
      if (existing != null) await showSession(existing);
      return existing == null;
    } catch (_) {
      rethrow;
    }
  }

  Future<void> submit() async {
    if (!formKey.currentState!.validate()) return;
    await run(() async {
      if (!await ensureReady()) return;
      final epoch = sessionEpoch;
      await widget.auth
          .setStaySignedIn(staySignedIn)
          .timeout(widget.requestTimeout);
      if (!mounted || epoch != sessionEpoch) return;
      final pending = register
          ? widget.auth.register(
              nickname.text.trim(),
              email.text.trim(),
              password.text,
            )
          : widget.auth.signIn(email.text.trim(), password.text);
      final value = await pending.timeout(widget.requestTimeout);
      await applyAuthResult(value, epoch);
    });
  }

  Future<void> logout() => run(() async {
    final uid = session?.uid;
    await widget.auth.signOut().timeout(widget.requestTimeout);
    if (mounted && (session == null || session?.uid == uid)) {
      await showSession(null);
    }
  });

  Future<void> submitProfile() async {
    if (!profileFormKey.currentState!.validate()) return;
    await run(() async {
      final uid = session?.uid;
      if (uid == null || session?.verified != true) return;
      final request = profileRequest;
      final saved = await widget.profiles
          .complete(uid, profileNickname.text.trim(), grade!)
          .timeout(widget.requestTimeout);
      if (!mounted || session?.uid != uid || request != profileRequest) return;
      if (saved.uid != uid) throw StateError('PROFILE_UID_MISMATCH');
      setState(() {
        profile = saved;
        step = saved.canOpenHome
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
  Widget build(BuildContext context) {
    if (!bootstrapping && step == AccessStep.ready && profile != null) {
      return Theme(
        data: Theme.of(context).copyWith(
          textTheme: Theme.of(context).textTheme.apply(fontFamily: 'Nunito'),
        ),
        child: AdventureHome(
          key: ValueKey(profile!.uid),
          profile: profile!,
          onLogout: logout,
          busy: busy,
          error: error,
        ),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFFEEF7F2),
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
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Color(0xFFDCEFE3),
                        shape: BoxShape.circle,
                      ),
                      child: Image.asset(
                        'assets/branding/splash-island.png',
                        width: 96,
                        height: 96,
                        fit: BoxFit.contain,
                        excludeFromSemantics: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Matematik Macera Evreni',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF173C45),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (step == AccessStep.credentials) ...[
                    const Text(
                      'Keşfet, öğren, kendi yolunu çiz.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF426252)),
                    ),
                    const SizedBox(height: 20),
                  ] else
                    const SizedBox(height: 20),
                  Text(
                    switch (step) {
                      AccessStep.credentials => 'Hoş geldin',
                      AccessStep.verification => 'E-postanızı doğrulayın',
                      AccessStep.profileForm => 'Profilini tamamla',
                      AccessStep.compliancePending => 'Hesap hazırlanıyor',
                      AccessStep.ready => 'Hazırsın',
                      AccessStep.profileError => 'Profil yüklenemedi',
                      AccessStep.accountBlocked => 'Hesap kullanılamıyor',
                      AccessStep.sessionError => 'Oturum doğrulanamadı',
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
                    if (!initialized)
                      OutlinedButton(
                        onPressed: busy ? null : restoreSession,
                        child: const Text('Oturumu yeniden kontrol et'),
                      ),
                    if (step == AccessStep.credentials)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: const Color(0xFFD4E4DA)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Material(
                            color: Colors.transparent,
                            child: credentialsView(),
                          ),
                        ),
                      ),
                    if (step == AccessStep.verification) verificationView(),
                    if (step == AccessStep.profileForm && !profileLoading)
                      profileFormView(),
                    if (step == AccessStep.compliancePending)
                      compliancePendingView(),
                    if (step == AccessStep.ready) readyView(),
                    if (step == AccessStep.profileError) profileErrorView(),
                    if (step == AccessStep.sessionError) ...[
                      const Text(
                        'Bağlantını kontrol et. Oturum doğrulanana kadar hesap alanı kapalı.',
                      ),
                      FilledButton(
                        onPressed: busy ? null : refreshSession,
                        child: const Text('Oturumu yeniden doğrula'),
                      ),
                      TextButton(
                        onPressed: busy ? null : logout,
                        child: const Text('Çıkış yap'),
                      ),
                    ],
                    if (step == AccessStep.accountBlocked) ...[
                      const Text(
                        'Hesabın şu anda kullanılamıyor. Başka bir hesapla giriş yapabilirsin.',
                      ),
                      TextButton(
                        onPressed: busy ? null : logout,
                        child: const Text('Çıkış yap'),
                      ),
                    ],
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
  }

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
        const SizedBox(height: 8),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text('Beni hatırla'),
          value: staySignedIn,
          onChanged: busy
              ? null
              : (value) => setState(() => staySignedIn = value ?? true),
        ),
        const SizedBox(height: 8),
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
                  await widget.auth
                      .setStaySignedIn(staySignedIn)
                      .timeout(widget.requestTimeout);
                  final epoch = sessionEpoch;
                  await applyAuthResult(
                    await widget.auth.signInWithGoogle().timeout(
                      widget.requestTimeout,
                    ),
                    epoch,
                  );
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
                    await widget.auth
                        .setStaySignedIn(staySignedIn)
                        .timeout(widget.requestTimeout);
                    final epoch = sessionEpoch;
                    await applyAuthResult(
                      await widget.auth.signInWithApple().timeout(
                        widget.requestTimeout,
                      ),
                      epoch,
                    );
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
                final epoch = sessionEpoch;
                await applyAuthResult(
                  await widget.auth.refresh().timeout(widget.requestTimeout),
                  epoch,
                );
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
