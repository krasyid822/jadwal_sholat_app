import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_compass_v2/flutter_compass_v2.dart';
import 'dart:math';
import 'dart:async';
import 'google_qibla_finder_screen.dart';

/// Screen untuk menampilkan arah kiblat dengan sistem kompas sederhana
/// Hanya needle.png yang bergerak, sisanya diam
class QiblaScreenSimple extends StatefulWidget {
  const QiblaScreenSimple({super.key});

  @override
  State<QiblaScreenSimple> createState() => _QiblaScreenSimpleState();
}

class _QiblaScreenSimpleState extends State<QiblaScreenSimple>
    with TickerProviderStateMixin {
  // Animation controller hanya untuk needle
  late AnimationController _needleAnimationController;
  late Animation<double> _needleRotation;

  // Tab controller
  late TabController _tabController;

  // State variables
  bool _isLoading = true;
  bool _hasError = false;
  String? _errorMessage;
  String? _locationInfo;

  // Compass data
  double _needleAngle = 0.0; // Sudut needle menunjuk ke kiblat (dalam derajat)
  double _currentHeading = 0.0; // Heading device saat ini
  double _qiblaDirection = 0.0; // Arah kiblat dari lokasi saat ini

  // Compass calibration variables
  bool _needsCalibration = false;
  bool _isCalibrating = false;
  double _compassAccuracy = 0.0; // Akurasi kompas (0-3)
  final List<double> _headingHistory =
      []; // Riwayat heading untuk deteksi stabilitas
  DateTime? _lastCalibrationCheck;

  // Auto-stop sensor when too many poor readings to reduce native log spam
  int _poorReadingStreak = 0;
  static const int _poorReadingThreshold = 12;
  // Whether the compass stream is intentionally active (started by user)
  bool _compassActive = false;

  // Throttle compass processing to reduce UI updates and native log pressure
  int _lastCompassProcessMs = 0;

  // Safe setState helper to avoid calling setState after widget disposed
  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  // Instruction collapse state
  bool _instructionsExpanded = false;

  // Location
  Position? _currentPosition;

  // Compass subscription
  StreamSubscription<CompassEvent>? _compassSubscription;

  // Ka'bah coordinates
  static const double _kaabaLatitude = 21.4225;
  static const double _kaabaLongitude = 39.8262;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Stop compass when leaving the Kompas Lokal tab to reduce native sensor
    // activity/logs. Do NOT auto-start to avoid automatic sensor activation;
    // user must explicitly start the compass via UI.
    _tabController.addListener(() {
      if (_tabController.index != 0) {
        _stopCompassStream();
      }
    });
    _initializeNeedleAnimation();
    _initializeCompass();
  }

  void _initializeNeedleAnimation() {
    _needleAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _needleRotation = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(
        parent: _needleAnimationController,
        curve: Curves.easeInOut,
      ),
    );
  }

  Future<void> _initializeCompass() async {
    try {
      setState(() {
        _isLoading = true;
        _hasError = false;
      });

      // Check and request permissions
      final hasPermission = await _checkAndRequestPermissions();
      if (!hasPermission) {
        throw Exception('Location permission required for qibla direction');
      }

      // Get current location
      await _getCurrentLocation();

      // Do NOT auto-start compass stream here. User should explicitly start
      // the compass (to avoid unnecessary native sensor activation and logs).

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = e.toString();
      });
    }
  }

  Future<bool> _checkAndRequestPermissions() async {
    final status = await Permission.location.status;
    if (status.isGranted) return true;

    final result = await Permission.location.request();
    return result.isGranted;
  }

  Future<void> _getCurrentLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services are disabled');
      }

      _currentPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      // Calculate qibla direction from current location
      _qiblaDirection = _calculateQiblaDirection(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
      );

      setState(() {
        _locationInfo =
            '${_currentPosition!.latitude.toStringAsFixed(6)}, ${_currentPosition!.longitude.toStringAsFixed(6)}';
      });
    } catch (e) {
      throw Exception('Failed to get location: $e');
    }
  }

  double _calculateQiblaDirection(double lat, double lng) {
    // Convert to radians
    final latRad = lat * (pi / 180);
    final lngRad = lng * (pi / 180);
    final kaabaLatRad = _kaabaLatitude * (pi / 180);
    final kaabaLngRad = _kaabaLongitude * (pi / 180);

    // Calculate bearing to Ka'bah
    final dLng = kaabaLngRad - lngRad;
    final y = sin(dLng) * cos(kaabaLatRad);
    final x =
        cos(latRad) * sin(kaabaLatRad) -
        sin(latRad) * cos(kaabaLatRad) * cos(dLng);

    final bearing = atan2(y, x) * (180 / pi);
    return (bearing + 360) % 360; // Normalize to 0-360 degrees
  }

  Future<void> _startCompassStream() async {
    try {
      final compassStream = FlutterCompass.events;
      if (compassStream == null) {
        throw Exception('Compass not available on this device');
      }

      // reset poor reading counter when starting
      _poorReadingStreak = 0;

      // If already subscribed, don't create a duplicate subscription
      if (_compassSubscription != null) {
        return;
      }

      _compassSubscription = compassStream.listen(
        (CompassEvent event) {
          final now = DateTime.now().millisecondsSinceEpoch;
          // process at most every 200ms
          if (now - _lastCompassProcessMs < 200) return;
          _lastCompassProcessMs = now;

          if (event.heading == null) return;
          _currentHeading = event.heading!;

          // Check compass accuracy if available
          if (event.accuracy != null) {
            _compassAccuracy = event.accuracy!.toDouble();
            _checkCompassCalibration();

            // Track consecutive poor readings and auto-stop sensor to
            // prevent large amounts of native log output from flutter_compass
            if (_compassAccuracy < 1.0) {
              _poorReadingStreak++;
            } else {
              _poorReadingStreak = 0;
            }

            if (_poorReadingStreak >= _poorReadingThreshold) {
              // Mark needs calibration and stop the native subscription
              _safeSetState(() {
                _needsCalibration = true;
              });
              _stopCompassStream();
              return; // don't process further noisy readings
            }
          }

          // Add to heading history for stability check
          _updateHeadingHistory(event.heading!);

          // Update needle position on UI thread safely
          _safeSetState(() {
            _updateNeedlePosition();
          });
        },
        onError: (error) {
          // Avoid printing repeated native plugin errors — show a concise
          // user-facing message instead and stop the subscription to silence logs.
          setState(() {
            _hasError = true;
            _errorMessage = 'Compass error';
          });
          _stopCompassStream();
        },
      );
    } catch (e) {
      throw Exception('Failed to start compass: $e');
    }
  }

  /// Stop the compass stream subscription to prevent native sensor/log spam.
  void _stopCompassStream() {
    try {
      _compassSubscription?.cancel();
    } catch (_) {}
    _compassSubscription = null;
  }

  /// Attempt to restart the compass stream (used after user performs
  /// calibration). Resets poor-reading counters and viewers.
  Future<void> _restartCompassStream() async {
    _poorReadingStreak = 0;
    _needsCalibration = false;
    _hasError = false;
    _errorMessage = null;
    await _startCompassStream();
  }

  void _updateNeedlePosition() {
    if (_currentPosition == null) return;

    // Needle menunjukkan arah ponsel (heading device)
    // Needle berputar mengikuti device heading
    _animateNeedleToAngle(_currentHeading);
  }

  void _animateNeedleToAngle(double targetAngle) {
    final currentAngle = _needleAngle;
    double angleDiff = targetAngle - currentAngle;

    // Handle angle wrapping for smooth transitions
    if (angleDiff > 180) angleDiff -= 360;
    if (angleDiff < -180) angleDiff += 360;

    setState(() {
      _needleAngle = currentAngle + angleDiff;
    });

    _needleRotation = Tween<double>(begin: currentAngle, end: _needleAngle)
        .animate(
          CurvedAnimation(
            parent: _needleAnimationController,
            curve: Curves.easeInOut,
          ),
        );

    _needleAnimationController.reset();
    _needleAnimationController.forward();
  }

  /// Update heading history untuk deteksi stabilitas kompas
  void _updateHeadingHistory(double heading) {
    _headingHistory.add(heading);

    // Keep only last 10 readings
    if (_headingHistory.length > 10) {
      _headingHistory.removeAt(0);
    }
  }

  /// Check compass calibration berdasarkan akurasi dan stabilitas
  void _checkCompassCalibration() {
    final now = DateTime.now();

    // Check calibration setiap 5 detik
    if (_lastCalibrationCheck != null &&
        now.difference(_lastCalibrationCheck!).inSeconds < 5) {
      return;
    }

    _lastCalibrationCheck = now;

    bool needsCalibration = false;

    // Check compass accuracy (0 = unreliable, 3 = high accuracy)
    if (_compassAccuracy < 1.0) {
      needsCalibration = true;
    }

    // Check heading stability
    if (_headingHistory.length >= 5) {
      final recentHeadings = _headingHistory.sublist(
        _headingHistory.length - 5,
      );
      final variation = _calculateHeadingVariation(recentHeadings);

      // Jika variasi terlalu besar (> 30 derajat), kompas tidak stabil
      if (variation > 30.0) {
        needsCalibration = true;
      }
    }

    if (needsCalibration != _needsCalibration) {
      setState(() {
        _needsCalibration = needsCalibration;
      });
    }
  }

  /// Calculate variation in heading values
  double _calculateHeadingVariation(List<double> headings) {
    if (headings.length < 2) return 0.0;

    double minHeading = headings[0];
    double maxHeading = headings[0];

    for (double heading in headings) {
      if (heading < minHeading) minHeading = heading;
      if (heading > maxHeading) maxHeading = heading;
    }

    double variation = maxHeading - minHeading;

    // Handle wrap-around (359° to 1°)
    if (variation > 180) {
      variation = 360 - variation;
    }

    return variation;
  }

  /// Start manual calibration process
  void _startCalibration() {
    setState(() {
      _isCalibrating = true;
      _needsCalibration = false;
    });

    // Auto-stop calibration after 15 seconds
    Timer(const Duration(seconds: 15), () {
      if (_isCalibrating) {
        setState(() {
          _isCalibrating = false;
        });
      }
    });
  }

  /// Stop calibration process
  void _stopCalibration() {
    setState(() {
      _isCalibrating = false;
    });
  }

  /// Get accuracy text from compass accuracy value
  String _getAccuracyText(double accuracy) {
    if (accuracy >= 3) return 'High';
    if (accuracy >= 2) return 'Medium';
    if (accuracy >= 1) return 'Low';
    return 'Unreliable';
  }

  /// Get current compass status
  String _getCompassStatus() {
    if (_isCalibrating) return 'Calibrating';
    if (_needsCalibration) return 'Needs Calibration';
    if (_compassAccuracy >= 2) return 'Good';
    if (_compassAccuracy >= 1) return 'Fair';
    return 'Poor';
  }

  @override
  void dispose() {
    _compassSubscription?.cancel();
    _needleAnimationController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text(
          'Arah Kiblat',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF121212),
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF4DB6AC),
          labelColor: const Color(0xFF4DB6AC),
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(icon: Icon(Icons.explore), text: 'Kompas Lokal'),
            Tab(icon: Icon(Icons.public), text: 'Google Qibla'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildLocalCompass(), const GoogleQiblaFinderScreen()],
      ),
    );
  }

  Widget _buildLocalCompass() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFF4DB6AC)),
            SizedBox(height: 16),
            Text(
              'Inisialisasi kompas...',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }

    if (_hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Error: $_errorMessage',
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _initializeCompass,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4DB6AC),
              ),
              child: const Text('Coba Lagi'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Calibration warning banner
        if (_needsCalibration || _isCalibrating)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: _isCalibrating ? const Color(0xFF4DB6AC) : Colors.orange,
            child: Row(
              children: [
                Icon(
                  _isCalibrating ? Icons.refresh : Icons.warning,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _isCalibrating
                        ? 'Kalibrasi kompas aktif - putar ponsel dalam gerakan angka 8'
                        : 'Kompas perlu dikalibrasi untuk akurasi yang lebih baik',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (!_isCalibrating)
                  Row(
                    children: [
                      TextButton(
                        onPressed: _startCalibration,
                        child: const Text(
                          'Kalibrasi',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                      // If we auto-stopped due to poor readings, allow the user
                      // to explicitly restart the compass after calibration.
                      if (_needsCalibration)
                        TextButton(
                          onPressed: _restartCompassStream,
                          child: const Text(
                            'Restart',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                    ],
                  )
                else
                  TextButton(
                    onPressed: _stopCalibration,
                    child: const Text(
                      'Stop',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),

        // Location info
        if (_locationInfo != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF1E1E1E),
            child: Column(
              children: [
                const Text(
                  'Lokasi Saat Ini',
                  style: TextStyle(
                    color: Color(0xFF4DB6AC),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _locationInfo!,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Text(
                  'Arah Kiblat: ${_qiblaDirection.toStringAsFixed(1)}°',
                  style: const TextStyle(
                    color: Color(0xFF81C784),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

        // Compass view
        Expanded(
          child: Center(
            child: SizedBox(
              width: 300,
              height: 300,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Compass body (static) - badan.png
                  Image.asset(
                    'assets/images/badan.png',
                    width: 280,
                    height: 280,
                    fit: BoxFit.contain,
                  ),

                  // Ka'bah indicator (positioned on compass edge at qibla direction)
                  Transform.rotate(
                    angle: _qiblaDirection * (pi / 180),
                    child: SizedBox(
                      width: 280,
                      height: 280,
                      child: Stack(
                        children: [
                          Positioned(
                            top: 10, // Position at edge of compass
                            left: 130, // Center horizontally
                            child: Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color: const Color(0xFF81C784),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                              child: const Icon(
                                Icons.location_on,
                                color: Colors.white,
                                size: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Needle (rotating) - needle.png menunjukkan arah ponsel
                  AnimatedBuilder(
                    animation: _needleRotation,
                    builder: (context, child) {
                      return Transform.rotate(
                        angle: (_needleRotation.value) * (pi / 180),
                        child: Image.asset(
                          'assets/images/jarum.png',
                          width: 200,
                          height: 200,
                          fit: BoxFit.contain,
                        ),
                      );
                    },
                  ),

                  // Center dot with calibration status indicator
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: _isCalibrating
                          ? Colors.orange
                          : _needsCalibration
                          ? Colors.red
                          : const Color(0xFF4DB6AC),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1),
                    ),
                  ),

                  // Calibration animation overlay
                  if (_isCalibrating)
                    SizedBox(
                      width: 280,
                      height: 280,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.orange.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),

        // Instructions
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: const Color(0xFF1E1E1E),
          child: Column(
            children: [
              /*  const Text(
                'Petunjuk Penggunaan',
                style: TextStyle(
                  color: Color(0xFF4DB6AC),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ), */
              /* const SizedBox(height: 8), */
              /* const Text(
                '• Jarum menunjukkan arah ponsel saat ini\n'
                '• Titik hijau di pinggiran kompas adalah arah Ka\'bah\n'
                '• Putar ponsel hingga jarum menunjuk ke titik hijau Ka\'bah\n'
                '• Saat jarum dan titik Ka\'bah sejajar, Anda menghadap kiblat\n\n'
                'Kalibrasi Kompas:\n'
                '• Jika kompas tidak akurat, lakukan kalibrasi\n'
                '• Putar ponsel dalam gerakan angka 8 untuk kalibrasi\n'
                '• Hindari objek magnetik saat menggunakan kompas',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ), */
              /* const SizedBox(height: 8), */
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      'Device Heading: ${_currentHeading.toStringAsFixed(1)}° | '
                      'Qibla Direction: ${_qiblaDirection.toStringAsFixed(1)}°\n'
                      'Compass Accuracy: ${_getAccuracyText(_compassAccuracy)} | '
                      'Status: ${_getCompassStatus()}',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 10,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      _instructionsExpanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                      color: Colors.white70,
                    ),
                    onPressed: () {
                      setState(() {
                        _instructionsExpanded = !_instructionsExpanded;
                      });
                    },
                    tooltip: _instructionsExpanded
                        ? 'Sembunyikan petunjuk'
                        : 'Tampilkan petunjuk',
                  ),
                ],
              ),

              // Collapsible instructions block
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: const Text(
                    '• Jarum menunjukkan arah ponsel saat ini\n'
                    '• Titik hijau di pinggiran kompas adalah arah Ka\'bah\n'
                    '• Putar ponsel hingga jarum menunjuk ke titik hijau Ka\'bah\n'
                    '• Saat jarum dan titik Ka\'bah sejajar, Anda menghadap kiblat\n\n'
                    'Kalibrasi Kompas:\n'
                    '• Jika kompas tidak akurat, lakukan kalibrasi\n'
                    '• Putar ponsel dalam gerakan angka 8 untuk kalibrasi\n'
                    '• Hindari objek magnetik saat menggunakan kompas',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
                crossFadeState: _instructionsExpanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 240),
              ),

              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: () async {
                      if (!_compassActive) {
                        // mark active and start
                        setState(() {
                          _compassActive = true;
                        });
                        await _startCompassStream();
                      } else {
                        // stop compass
                        _stopCompassStream();
                        setState(() {
                          _compassActive = false;
                        });
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4DB6AC),
                    ),
                    child: Text(
                      _compassActive ? 'Hentikan Kompas' : 'Mulai Kompas',
                    ),
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
