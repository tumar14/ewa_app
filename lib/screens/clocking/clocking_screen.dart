import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../models/employee.dart';
import '../../models/time_session.dart';
import '../../utils/pin_hasher.dart';
import '../../providers/settings_providers.dart';
import '../../providers/time_session_providers.dart';
import '../../providers/firebase_providers.dart';
import '../../providers/employee_providers.dart';
import '../../services/time_session_repository.dart';
import '../../theme/glass_theme.dart';
import '../../widgets/glass_components.dart';

/// Best-effort photo capture for shared-kiosk punches (spec section 6,
/// buddy-punching mitigation). Never blocks the punch: if the camera is
/// unavailable or the operator dismisses it, we just skip the photo.
Future<XFile?> _capturePunchPhotoOrNull() async {
  try {
    return await ImagePicker().pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      imageQuality: 60,
      maxWidth: 800,
    );
  } catch (_) {
    return null;
  }
}

/// Clocks [employeeId] in/out against the current open session, attaching
/// a punch photo when one was captured, and returns a short status
/// message for the kiosk operator (including a flagged-for-review notice).
Future<String> _performKioskPunch({
  required TimeSessionRepository sessionRepo,
  required String employeeId,
  required String employeeName,
  required ClockEventSource source,
  required XFile? photo,
}) async {
  final open = await sessionRepo.watchOpenSession(employeeId).first;
  if (open != null) {
    await sessionRepo.clockOut(open.id, DateTime.now());
    if (photo != null) {
      await sessionRepo.uploadPunchPhoto(open.id, photo);
    }
    return '$employeeName clocked out.';
  }

  final result = await sessionRepo.clockIn(
    TimeSession(
      id: '',
      employeeId: employeeId,
      clockIn: DateTime.now(),
      source: source,
    ),
  );
  if (photo != null) {
    await sessionRepo.uploadPunchPhoto(result.sessionId, photo);
  }
  return result.flagged
      ? '$employeeName clocked in. Flagged for supervisor review '
          '(another punch happened seconds earlier).'
      : '$employeeName clocked in.';
}

/// Body-only clocking widget — embeds in WorkerHomeScreen's tab.
class ClockingBody extends ConsumerWidget {
  final String employeeId;

  const ClockingBody({super.key, required this.employeeId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider).valueOrNull;
    final clockSource = settings?.clockSource ?? ClockSource.manual;
    return switch (clockSource) {
      ClockSource.manual => _ManualClocking(employeeId: employeeId),
      ClockSource.kioskPin => const _KioskPinClocking(),
      ClockSource.kioskQr => const _KioskQrClocking(),
      ClockSource.externalImport => const _ExternalImportNotice(),
    };
  }
}

/// Standalone screen used when navigating directly (e.g. admin kiosk).
class ClockingScreen extends ConsumerWidget {
  final String employeeId;

  const ClockingScreen({super.key, required this.employeeId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(title: const Text('Clock In / Out')),
      body: GlassBackground(child: ClockingBody(employeeId: employeeId)),
    );
  }
}

class _ManualClocking extends ConsumerStatefulWidget {
  final String employeeId;

  const _ManualClocking({required this.employeeId});

  @override
  ConsumerState<_ManualClocking> createState() => _ManualClockingState();
}

class _ManualClockingState extends ConsumerState<_ManualClocking> {
  bool _loading = false;

  Future<void> _clockIn() async {
    setState(() => _loading = true);
    try {
      await ref.read(timeSessionRepositoryProvider).clockIn(
            TimeSession(
              id: '',
              employeeId: widget.employeeId,
              clockIn: DateTime.now(),
              source: ClockEventSource.manual,
            ),
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Clock in failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _clockOut(String sessionId) async {
    setState(() => _loading = true);
    try {
      await ref
          .read(timeSessionRepositoryProvider)
          .clockOut(sessionId, DateTime.now());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Clock out failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final openSession = ref.watch(openSessionProvider(widget.employeeId));
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: openSession.when(
        loading: () => const CircularProgressIndicator(),
        error: (e, _) => Text('Error: $e'),
        data: (session) {
          final isClockedIn = session != null;
          return Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isClockedIn
                        ? glassSuccess.withOpacity(0.12)
                        : const Color(0x14FFFFFF),
                    border: Border.all(
                      color: isClockedIn
                          ? glassSuccess.withOpacity(0.35)
                          : const Color(0x21FFFFFF),
                      width: 2,
                    ),
                    boxShadow: isClockedIn
                        ? [
                            BoxShadow(
                              color: glassSuccess.withOpacity(0.20),
                              blurRadius: 20,
                            ),
                          ]
                        : [],
                  ),
                  child: Icon(
                    isClockedIn ? Icons.timer : Icons.timer_off_outlined,
                    size: 52,
                    color: isClockedIn
                        ? glassSuccess
                        : const Color(0x80FFFFFF),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  isClockedIn ? 'Currently clocked in' : 'Not clocked in',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                if (isClockedIn) ...[
                  Text(
                    'Since ${_formatTime(session.clockIn)}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 4),
                  _ElapsedTimer(clockIn: session.clockIn),
                ] else
                  Text(
                    'Tap the button below to start your shift',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                    textAlign: TextAlign.center,
                  ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: isClockedIn
                      ? OutlinedButton.icon(
                          icon: _loading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.stop_circle_outlined),
                          label: const Text('Clock Out'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: cs.error,
                            side: BorderSide(color: cs.error),
                          ),
                          onPressed: _loading ? null : () => _clockOut(session.id),
                        )
                      : FilledButton.icon(
                          icon: _loading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.play_circle_outlined),
                          label: const Text('Clock In'),
                          onPressed: _loading ? null : _clockIn,
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  static String _formatTime(DateTime dt) {
    final l = dt.toLocal();
    final h = l.hour.toString().padLeft(2, '0');
    final m = l.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _ElapsedTimer extends StatefulWidget {
  final DateTime clockIn;
  const _ElapsedTimer({required this.clockIn});

  @override
  State<_ElapsedTimer> createState() => _ElapsedTimerState();
}

class _ElapsedTimerState extends State<_ElapsedTimer> {
  late final Stream<int> _ticks =
      Stream.periodic(const Duration(seconds: 1), (i) => i);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: _ticks,
      builder: (context, _) {
        final elapsed = DateTime.now().difference(widget.clockIn);
        final h = elapsed.inHours.toString().padLeft(2, '0');
        final m = (elapsed.inMinutes % 60).toString().padLeft(2, '0');
        final s = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
        return Text(
          '$h:$m:$s',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                color: glassSuccess,
                fontWeight: FontWeight.bold,
              ),
        );
      },
    );
  }
}

class _KioskPinClocking extends ConsumerStatefulWidget {
  const _KioskPinClocking();

  @override
  ConsumerState<_KioskPinClocking> createState() => _KioskPinClockingState();
}

class _KioskPinClockingState extends ConsumerState<_KioskPinClocking> {
  final _pinController = TextEditingController();
  String? _message;
  bool _submitting = false;

  // Rate-limiting state — shared across the kiosk session.
  static int _failedAttempts = 0;
  static DateTime? _lockedUntil;
  static const _maxAttempts = 5;
  static const _lockDuration = Duration(seconds: 60);

  bool get _isLocked {
    if (_lockedUntil == null) return false;
    if (DateTime.now().isAfter(_lockedUntil!)) {
      _lockedUntil = null;
      _failedAttempts = 0;
      return false;
    }
    return true;
  }

  String get _lockMessage {
    final remaining = _lockedUntil!.difference(DateTime.now()).inSeconds;
    return 'Too many incorrect attempts. Try again in $remaining s.';
  }

  bool _verifyPin(Employee employee, String entered) {
    if (employee.pin == null) return false;
    if (employee.pinSalt == null) {
      // Legacy: plaintext comparison
      return employee.pin == entered;
    }
    return PinHasher.verifyPin(entered, employee.pin!, employee.pinSalt!);
  }

  Future<void> _submitPin() async {
    if (_submitting) return;
    if (_isLocked) {
      setState(() => _message = _lockMessage);
      return;
    }

    final pin = _pinController.text.trim();
    final employees = await ref.read(allEmployeesProvider.future);
    final match = employees.where((e) => _verifyPin(e, pin)).toList();

    if (match.isEmpty) {
      _failedAttempts++;
      if (_failedAttempts >= _maxAttempts) {
        _lockedUntil = DateTime.now().add(_lockDuration);
        setState(() => _message = _lockMessage);
      } else {
        final remaining = _maxAttempts - _failedAttempts;
        setState(() => _message =
            'PIN not recognized. $remaining attempt${remaining == 1 ? '' : 's'} remaining.');
      }
      _pinController.clear();
      return;
    }

    _failedAttempts = 0;
    _lockedUntil = null;

    final employee = match.first;
    setState(() {
      _submitting = true;
      _message = 'Say cheese...';
    });

    final photo = await _capturePunchPhotoOrNull();
    final sessionRepo = ref.read(timeSessionRepositoryProvider);
    final message = await _performKioskPunch(
      sessionRepo: sessionRepo,
      employeeId: employee.id,
      employeeName: employee.name,
      source: ClockEventSource.kioskPin,
      photo: photo,
    );

    if (mounted) {
      setState(() {
        _message = message;
        _submitting = false;
      });
    }
    _pinController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Enter your 4-digit PIN', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              TextField(
                controller: _pinController,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 4,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 28, letterSpacing: 8),
                onSubmitted: (_) => _submitPin(),
              ),
              FilledButton(
                onPressed: _submitting ? null : _submitPin,
                child: _submitting
                    ? const SizedBox(
                        width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Submit'),
              ),
              if (_message != null) ...[
                const SizedBox(height: 12),
                Text(_message!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _KioskQrClocking extends ConsumerStatefulWidget {
  const _KioskQrClocking();

  @override
  ConsumerState<_KioskQrClocking> createState() => _KioskQrClockingState();
}

class _KioskQrClockingState extends ConsumerState<_KioskQrClocking> {
  final _scannerController = MobileScannerController(
    detectionTimeoutMs: 1000,
    facing: CameraFacing.back,
  );

  bool _isProcessing = false;
  String? _message;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _handleDetection(BarcodeCapture capture) async {
    if (_isProcessing) return;

    final code = capture.barcodes
        .map((barcode) => barcode.rawValue ?? barcode.displayValue)
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .firstOrNull;

    if (code == null) return;

    setState(() {
      _isProcessing = true;
      _message = 'Checking code...';
    });
    await _scannerController.stop();

    try {
      final employees = await ref.read(allEmployeesProvider.future);
      final match = employees.where((e) => e.qrCode?.trim() == code).toList();

      if (!mounted) return;
      if (match.isEmpty) {
        setState(() => _message = 'Code not recognized.');
        return;
      }

      final employee = match.first;
      if (!mounted) return;
      setState(() => _message = 'Say cheese...');

      final photo = await _capturePunchPhotoOrNull();
      final sessionRepo = ref.read(timeSessionRepositoryProvider);
      final message = await _performKioskPunch(
        sessionRepo: sessionRepo,
        employeeId: employee.id,
        employeeName: employee.name,
        source: ClockEventSource.kioskQr,
        photo: photo,
      );

      if (!mounted) return;
      setState(() => _message = message);
    } catch (e) {
      if (mounted) {
        setState(() => _message = 'Unable to process scan: $e');
      }
    } finally {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (mounted) {
        setState(() => _isProcessing = false);
        await _scannerController.start();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: _scannerController,
          onDetect: _handleDetection,
          errorBuilder: (context, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Camera unavailable: ${error.errorCode.message}',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
        IgnorePointer(
          child: Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 24,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_message != null)
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Text(
                      _message!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colorScheme.onSurface),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.filled(
                    tooltip: 'Toggle torch',
                    onPressed: _scannerController.toggleTorch,
                    icon: const Icon(Icons.flashlight_on_outlined),
                  ),
                  const SizedBox(width: 12),
                  IconButton.filled(
                    tooltip: 'Switch camera',
                    onPressed: _scannerController.switchCamera,
                    icon: const Icon(Icons.cameraswitch_outlined),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (iterator.moveNext()) {
      return iterator.current;
    }
    return null;
  }
}

class _ExternalImportNotice extends StatelessWidget {
  const _ExternalImportNotice();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Hours are imported automatically from the company\'s existing '
          'attendance system. Clock in/out here is disabled.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
