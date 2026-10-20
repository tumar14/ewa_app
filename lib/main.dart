import 'widgets/brand_mark.dart';
import 'brand.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firebase_options.dart';
import 'theme/glass_theme.dart';
import 'widgets/glass_components.dart';
import 'providers/auth_providers.dart';
import 'providers/company_providers.dart';
import 'providers/firebase_providers.dart';
import 'providers/theme_providers.dart';
import 'screens/auth/consent_screen.dart';
import 'screens/auth/force_change_password_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/worker/worker_home_screen.dart';
import 'screens/admin/admin_shell.dart';
import 'screens/supervisor/supervisor_shell.dart';
import 'screens/platform_admin/platform_admin_shell.dart';

@pragma('vm:entry-point')
Future<void> _backgroundMessageHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

/// Opt-in local testing: `flutter run -d chrome --dart-define=USE_EMULATORS=true`
/// points Auth, Firestore and Functions at the Firebase emulators instead of the
/// live project. On an Android emulator also pass `--dart-define=EMULATOR_HOST=10.0.2.2`.
/// Compiled out of normal builds, which never read these defines.
const _useEmulators = bool.fromEnvironment('USE_EMULATORS');
const _emulatorHost = String.fromEnvironment('EMULATOR_HOST', defaultValue: '127.0.0.1');
const _emulatorProject = String.fromEnvironment('EMULATOR_PROJECT');

/// App Check proves a request comes from the real app, not a script. Off unless the build
/// is made with `--dart-define=APP_CHECK=true` (and, on the web, `APP_CHECK_SITE_KEY`) after
/// the console setup described in the README; the server only enforces it when
/// ENFORCE_APP_CHECK=true. Never on with the emulators.
const _appCheck = bool.fromEnvironment('APP_CHECK');
const _appCheckSiteKey = String.fromEnvironment('APP_CHECK_SITE_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final options = DefaultFirebaseOptions.currentPlatform;
  await Firebase.initializeApp(
    // Normally emulator mode keeps the app's own project id (Android ignores
    // any override and always uses google-services.json), so the emulators are
    // started under that id. EMULATOR_PROJECT is only for automated web tests.
    options: _useEmulators && _emulatorProject.isNotEmpty
        ? FirebaseOptions(
            apiKey: options.apiKey,
            appId: options.appId,
            messagingSenderId: options.messagingSenderId,
            projectId: _emulatorProject,
            storageBucket: options.storageBucket,
            authDomain: options.authDomain,
          )
        : options,
  );

  if (_appCheck && !_useEmulators) {
    await FirebaseAppCheck.instance.activate(
      androidProvider: kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
      appleProvider: kDebugMode ? AppleProvider.debug : AppleProvider.appAttestWithDeviceCheckFallback,
      webProvider: _appCheckSiteKey.isEmpty ? null : ReCaptchaV3Provider(_appCheckSiteKey),
    );
  }

  if (_useEmulators) {
    await FirebaseAuth.instance.useAuthEmulator(_emulatorHost, 9099);
    FirebaseFirestore.instance.useFirestoreEmulator(_emulatorHost, 8080);
    FirebaseFunctions.instance.useFunctionsEmulator(_emulatorHost, 5001);
  }

  // Crashlytics — mobile only (not supported on web)
  if (!kIsWeb) {
    await FirebaseCrashlytics.instance
        .setCrashlyticsCollectionEnabled(!kDebugMode);
    FlutterError.onError =
        FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
    FirebaseMessaging.onBackgroundMessage(_backgroundMessageHandler);
  }
  runApp(const ProviderScope(child: EwaApp()));
}

class EwaApp extends ConsumerWidget {
  const EwaApp({super.key});

  static final _analytics = FirebaseAnalytics.instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: Brand.appTitle,
      debugShowCheckedModeBanner: false,
      // Web analytics loads gtag.js from the internet and holds up first paint
      // until it arrives, which leaves a blank page on a slow or blocked link.
      navigatorObservers: [
        if (!kIsWeb) FirebaseAnalyticsObserver(analytics: _analytics),
      ],
      theme: buildGlassThemeLight(),
      darkTheme: buildGlassTheme(),
      themeMode: themeMode,
      builder: brandAppBuilder,
      home: const AuthGate(),
    );
  }
}

/// Routes by auth state → employee profile → consent → password change → role.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return authState.when(
      loading: () => const _SplashScreen(),
      error: (e, _) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: glassDanger),
                const SizedBox(height: 16),
                const Text(
                  'Something went wrong loading your account.\nPlease restart the app or contact HR.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
      data: (user) {
        if (user == null) return const LoginScreen();

        // Resolve companyId/platformAdmin from the ID token FIRST — with
        // company data under companies/{companyId}/employees/{uid}, the
        // client can't even construct the path to its own employee doc
        // without knowing companyId, let alone decide whether to show the
        // platform-admin shell instead.
        final tenantAsync = ref.watch(tenantProvider);
        return tenantAsync.when(
          loading: () => const _SplashScreen(),
          error: (e, _) => const _LoadErrorScreen(),
          data: (tenant) {
            if (tenant?.platformAdmin ?? false) {
              return const PlatformAdminShell();
            }

            final companyId = tenant?.companyId;
            if (companyId == null) {
              return const _NoCompanyScreen();
            }

            final employeeAsync = ref.watch(currentEmployeeProvider);
            return employeeAsync.when(
              loading: () => const _SplashScreen(),
              error: (e, _) => const _LoadErrorScreen(),
              data: (employee) {
                if (employee == null) {
                  return _NotLinkedScreen(companyId: companyId);
                }

                // Gate 1: consent must be recorded before the app is used.
                if (employee.consentedAt == null) {
                  return ConsentScreen(employeeId: employee.id);
                }

                // Gate 2: temporary password must be changed before continuing.
                if (employee.mustChangePassword) {
                  return ForceChangePasswordScreen(employeeId: employee.id);
                }

                return _FcmSetup(
                  employeeId: employee.id,
                  child: switch (employee.role) {
                    'admin' => const AdminShell(),
                    'supervisor' => const SupervisorShell(),
                    _ => WorkerHomeScreen(employeeId: employee.id),
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

class _LoadErrorScreen extends StatelessWidget {
  const _LoadErrorScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: glassDanger),
              const SizedBox(height: 16),
              const Text(
                'Something went wrong loading your account.\nPlease restart the app or contact HR.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Signed in, but no `companyId` claim and not a platform admin — e.g. an
/// Auth account created outside the app's own onboarding flows. There's no
/// company to look up an HR contact from, so this stays generic.
class _NoCompanyScreen extends ConsumerWidget {
  const _NoCompanyScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.person_search_outlined,
                  size: 64, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 16),
              const Text(
                'Account not set up yet',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your account isn\'t linked to a company yet. Please contact '
                'your workplace administrator to get started.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => ref.read(authServiceProvider).signOut(),
                child: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Signed in with a resolved company, but no employee doc under it (e.g. a
/// deactivated/removed profile). Unlike [_NoCompanyScreen], we DO know the
/// company here, so we can show its real HR contact instead of a hardcoded
/// one.
class _NotLinkedScreen extends ConsumerWidget {
  final String companyId;
  const _NotLinkedScreen({required this.companyId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final company = ref.watch(companyByIdProvider(companyId)).valueOrNull;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.person_search_outlined,
                  size: 64, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 16),
              const Text(
                'Account not set up yet',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your account hasn\'t been linked to an employee '
                'profile. Please contact HR to get started.',
                textAlign: TextAlign.center,
              ),
              if (company != null && company.hrEmail.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  company.hrEmail,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => ref.read(authServiceProvider).signOut(),
                child: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FcmSetup extends ConsumerStatefulWidget {
  final String employeeId;
  final Widget child;

  const _FcmSetup({required this.employeeId, required this.child});

  @override
  ConsumerState<_FcmSetup> createState() => _FcmSetupState();
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GlassBackground(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandMark(size: 84),
              const SizedBox(height: 20),
              Text(
                Brand.name,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                Brand.tagline,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 40),
              const CircularProgressIndicator(color: glassBlue),
            ],
          ),
        ),
      ),
    );
  }
}

class _FcmSetupState extends ConsumerState<_FcmSetup> {
  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // Web push needs a VAPID key and firebase-messaging-sw.js, not set up yet.
    if (kIsWeb) return;
    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission();
    if (settings.authorizationStatus != AuthorizationStatus.authorized &&
        settings.authorizationStatus != AuthorizationStatus.provisional) {
      return;
    }

    final token = await messaging.getToken();
    if (token != null) {
      await ref
          .read(employeeRepositoryProvider)
          .updateFcmToken(widget.employeeId, token);
    }

    messaging.onTokenRefresh.listen((newToken) {
      ref
          .read(employeeRepositoryProvider)
          .updateFcmToken(widget.employeeId, newToken);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
