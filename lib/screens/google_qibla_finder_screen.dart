import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Google Qibla Finder Screen - Versi Simple dan Stabil
class GoogleQiblaFinderScreen extends StatefulWidget {
  const GoogleQiblaFinderScreen({super.key});

  @override
  State<GoogleQiblaFinderScreen> createState() =>
      _GoogleQiblaFinderScreenState();
}

class _GoogleQiblaFinderScreenState extends State<GoogleQiblaFinderScreen> {
  WebViewController? _controller;
  bool _isLoading = true;
  bool _hasError = false;
  String? _errorMessage;
  Position? _currentPosition;
  bool _cameraPermissionGranted = false;
  Timer? _injectTimer;
  // Desired GPS accuracy (meters) before opening the WebView
  final double _desiredAccuracyMeters = 5.0;
  // Maximum time to try to improve accuracy (seconds)
  final int _maxAccuracyWaitSeconds = 45;
  // Status message shown while trying to improve GPS accuracy
  String _statusMessage = 'Mencari lokasi akurat...';

  // Safe setState helper to avoid calling setState after widget disposed
  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  @override
  void initState() {
    super.initState();
    _loadCachedPosition().then((_) => _initializeQiblaFinder());
  }

  Future<void> _initializeQiblaFinder() async {
    _safeSetState(() {
      _isLoading = true;
      _hasError = false;
      _statusMessage = 'Memeriksa izin lokasi dan kamera...';
    });

    // 1) Ensure location permission and services
    LocationPermission permission = LocationPermission.denied;
    try {
      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
    } catch (e) {
      debugPrint('⚠️ Error while checking/requesting location permission: $e');
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _safeSetState(() {
        _hasError = true;
        _isLoading = false;
        _errorMessage = permission == LocationPermission.deniedForever
            ? 'Izin lokasi permanen ditolak. Silakan buka pengaturan aplikasi.'
            : 'Izin lokasi diperlukan untuk menentukan arah kiblat.';
      });
      return;
    }

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _safeSetState(() {
        _hasError = true;
        _isLoading = false;
        _errorMessage = 'Layanan lokasi tidak aktif. Mohon aktifkan GPS.';
      });
      return;
    }

    // 2) Get a quick initial position (fast fallback)
    await _getCurrentLocation();

    // 3) Try to improve accuracy before opening the WebView
    setState(() {
      _statusMessage =
          'Meningkatkan akurasi GPS (mencoba hingga ${_maxAccuracyWaitSeconds}s)...';
    });
    bool achieved = await _ensureHighAccuracyPosition(
      _desiredAccuracyMeters,
      _maxAccuracyWaitSeconds,
    );

    // If we achieved high accuracy, cache the best position for faster next-open
    if (achieved && _currentPosition != null) {
      await _saveCachedPosition(_currentPosition!);
    }

    // 4) Request camera permission (required for web features)
    await _requestCameraPermission();

    // 5) Final decision: open the WebView. If accuracy not achieved, proceed with best effort but notify user.
    if (!achieved) {
      setState(() {
        _statusMessage =
            'Tidak mencapai akurasi tinggi, membukakan Qibla Finder dengan akurasi terbaik yang ada.';
      });
    } else {
      setState(() {
        _statusMessage = 'Akurasi mencukupi, membuka Qibla Finder...';
      });
    }

    // Small delay to let user see status
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;

    _initializeWebView();
  }

  /// Try to obtain a position with accuracy <= [targetMeters] within [timeoutSeconds].
  /// Returns true when target accuracy achieved, false on timeout (but leaves best reading in _currentPosition).
  Future<bool> _ensureHighAccuracyPosition(
    double targetMeters,
    int timeoutSeconds,
  ) async {
    Position? best = _currentPosition;

    // If current is already good, return immediately
    if (best != null && best.accuracy <= targetMeters) {
      debugPrint(
        '✅ Initial position already meets desired accuracy: ${best.accuracy}m',
      );
      return true;
    }

    // Start listening to position stream to collect improvements
    Stream<Position> stream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      ),
    );

    final Completer<bool> completer = Completer<bool>();

    StreamSubscription<Position>? sub;
    sub = stream.listen(
      (Position pos) {
        debugPrint(
          '🔁 Stream reading: ${pos.latitude}, ${pos.longitude} (±${pos.accuracy}m)',
        );
        if (best == null || pos.accuracy < best!.accuracy) {
          best = pos;
          setState(() {
            _currentPosition = best;
            _statusMessage = 'Akurasi: ±${best!.accuracy.toStringAsFixed(1)}m';
          });
        }

        if (best != null && best!.accuracy <= targetMeters) {
          debugPrint('🎯 Desired accuracy achieved: ${best!.accuracy}m');
          sub?.cancel();
          if (!completer.isCompleted) completer.complete(true);
        }
      },
      onError: (e) {
        debugPrint('⚠️ Position stream error: $e');
      },
    );

    // Timeout watcher - single timer
    Timer? timer;
    timer = Timer(Duration(seconds: timeoutSeconds), () {
      if (!completer.isCompleted) {
        debugPrint(
          '⏱ Timeout while waiting for high accuracy. Best accuracy: ${best?.accuracy ?? double.infinity}m',
        );
        sub?.cancel();
        setState(() {
          _currentPosition = best;
        });
        completer.complete(false);
      }
    });

    // Ensure timer is cancelled when completed early
    completer.future.whenComplete(() {
      timer?.cancel();
    });

    return completer.future;
  }

  Future<void> _requestCameraPermission() async {
    try {
      debugPrint('📷 Requesting camera permission...');

      PermissionStatus status = await Permission.camera.status;
      debugPrint('📷 Current camera permission status: $status');

      if (status.isDenied) {
        status = await Permission.camera.request();
        debugPrint('📷 Camera permission request result: $status');
      }

      setState(() {
        _cameraPermissionGranted = status.isGranted;
      });

      if (status.isGranted) {
        debugPrint('✅ Camera permission granted');
      } else if (status.isPermanentlyDenied) {
        debugPrint('🚫 Camera permission permanently denied');
        // Show dialog to open settings if needed
      } else {
        debugPrint('❌ Camera permission denied');
      }
    } catch (e) {
      debugPrint('⚠️ Error requesting camera permission: $e');
      setState(() {
        _cameraPermissionGranted = false;
      });
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      // Check and request location permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _hasError = true;
          _errorMessage = 'Izin lokasi diperlukan untuk menentukan arah kiblat';
        });
        return;
      }

      if (permission == LocationPermission.denied) {
        setState(() {
          _hasError = true;
          _errorMessage = 'Izin lokasi ditolak';
        });
        return;
      }

      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _hasError = true;
          _errorMessage = 'Layanan lokasi tidak aktif. Mohon aktifkan GPS.';
        });
        return;
      }

      debugPrint('🎯 Starting multi-layer GPS positioning...');

      // Layer 1: Fast initial position
      try {
        _currentPosition = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            distanceFilter: 0,
            timeLimit: Duration(seconds: 10),
          ),
        );
        debugPrint(
          '📍 Layer 1 GPS: ${_currentPosition!.latitude}, ${_currentPosition!.longitude} (±${_currentPosition!.accuracy}m)',
        );
      } catch (e) {
        debugPrint('⚠️ Layer 1 GPS failed: $e');
      }

      // Layer 2: High accuracy position
      try {
        Position highAccuracyPosition = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.best,
            distanceFilter: 0,
            timeLimit: Duration(seconds: 30),
          ),
        );

        if (_currentPosition == null ||
            highAccuracyPosition.accuracy < _currentPosition!.accuracy) {
          _currentPosition = highAccuracyPosition;
        }
        debugPrint(
          '📍 Layer 2 GPS: ${_currentPosition!.latitude}, ${_currentPosition!.longitude} (±${_currentPosition!.accuracy}m)',
        );
      } catch (e) {
        debugPrint('⚠️ Layer 2 GPS failed: $e');
      }

      // Layer 3: Navigation-grade position (ultimate precision)
      try {
        Position navigationPosition = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 0,
            timeLimit: Duration(seconds: 20),
          ),
        );

        if (_currentPosition == null ||
            navigationPosition.accuracy < _currentPosition!.accuracy) {
          _currentPosition = navigationPosition;
        }
        debugPrint(
          '📍 Layer 3 GPS: ${_currentPosition!.latitude}, ${_currentPosition!.longitude} (±${_currentPosition!.accuracy}m)',
        );
      } catch (e) {
        debugPrint('⚠️ Layer 3 GPS failed: $e');
      }

      // Layer 4: Multiple readings average for ultimate stability
      if (_currentPosition != null && _currentPosition!.accuracy > 5.0) {
        debugPrint(
          '🔄 Layer 4: Taking multiple readings for enhanced accuracy...',
        );
        List<Position> readings = [_currentPosition!];

        for (int i = 0; i < 3; i++) {
          try {
            await Future.delayed(const Duration(seconds: 2));
            Position reading = await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.bestForNavigation,
                distanceFilter: 0,
                timeLimit: Duration(seconds: 10),
              ),
            );
            readings.add(reading);
            debugPrint(
              '📍 Reading ${i + 2}: ${reading.latitude}, ${reading.longitude} (±${reading.accuracy}m)',
            );
          } catch (e) {
            debugPrint('⚠️ Reading ${i + 2} failed: $e');
          }
        }

        // Calculate weighted average based on accuracy
        if (readings.length > 1) {
          double totalWeight = 0;
          double weightedLat = 0;
          double weightedLng = 0;
          double bestAccuracy = double.infinity;

          for (Position reading in readings) {
            double weight =
                1.0 /
                (reading.accuracy + 1.0); // Higher weight for better accuracy
            totalWeight += weight;
            weightedLat += reading.latitude * weight;
            weightedLng += reading.longitude * weight;
            if (reading.accuracy < bestAccuracy) {
              bestAccuracy = reading.accuracy;
            }
          }

          if (totalWeight > 0) {
            double avgLat = weightedLat / totalWeight;
            double avgLng = weightedLng / totalWeight;

            // Create enhanced position with averaged coordinates
            _currentPosition = Position(
              latitude: avgLat,
              longitude: avgLng,
              accuracy: bestAccuracy * 0.7, // Enhanced accuracy from averaging
              altitude: _currentPosition!.altitude,
              altitudeAccuracy: _currentPosition!.altitudeAccuracy,
              heading: _currentPosition!.heading,
              headingAccuracy: _currentPosition!.headingAccuracy,
              speed: _currentPosition!.speed,
              speedAccuracy: _currentPosition!.speedAccuracy,
              timestamp: DateTime.now(),
            );
            debugPrint(
              '🎯 Layer 4 Final: ${_currentPosition!.latitude}, ${_currentPosition!.longitude} (±${_currentPosition!.accuracy}m)',
            );
          }
        }
      }

      if (_currentPosition == null) {
        throw Exception('Failed to obtain GPS position after all attempts');
      }

      debugPrint(
        '✅ Final GPS Result: ${_currentPosition!.latitude.toStringAsFixed(8)}, ${_currentPosition!.longitude.toStringAsFixed(8)} (±${_currentPosition!.accuracy.toStringAsFixed(1)}m)',
      );
    } catch (e) {
      setState(() {
        _hasError = true;
        _errorMessage = 'Gagal mendapatkan lokasi: $e';
      });
    }
  }

  // SharedPreferences cache keys
  static const String _cacheKeyLat = 'qibla_cached_lat';
  static const String _cacheKeyLon = 'qibla_cached_lon';
  static const String _cacheKeyAcc = 'qibla_cached_acc';
  static const String _cacheKeyTs = 'qibla_cached_ts';

  Future<void> _loadCachedPosition() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(_cacheKeyLat) && prefs.containsKey(_cacheKeyLon)) {
        final lat = prefs.getDouble(_cacheKeyLat)!;
        final lon = prefs.getDouble(_cacheKeyLon)!;
        final acc = prefs.getDouble(_cacheKeyAcc) ?? 9999.0;
        final ts =
            prefs.getInt(_cacheKeyTs) ?? DateTime.now().millisecondsSinceEpoch;

        // Invalidate cache older than 30 minutes
        const int expiryMs = 30 * 60 * 1000; // 30 minutes
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - ts > expiryMs) {
          debugPrint(
            '♻️ Cached Qibla position expired, ignoring (age ${(now - ts) / 1000}s)',
          );
          return;
        }

        _currentPosition = Position(
          latitude: lat,
          longitude: lon,
          accuracy: acc,
          altitude: 0.0,
          heading: 0.0,
          headingAccuracy: 0.0,
          speed: 0.0,
          speedAccuracy: 0.0,
          timestamp: DateTime.fromMillisecondsSinceEpoch(ts),
          altitudeAccuracy: 0.0,
        );

        debugPrint('📥 Loaded cached Qibla position: $lat, $lon (±${acc}m)');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load cached position: $e');
    }
  }

  Future<void> _saveCachedPosition(Position pos) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_cacheKeyLat, pos.latitude);
      await prefs.setDouble(_cacheKeyLon, pos.longitude);
      await prefs.setDouble(_cacheKeyAcc, pos.accuracy);
      await prefs.setInt(_cacheKeyTs, pos.timestamp.millisecondsSinceEpoch);
      debugPrint(
        '📤 Saved cached Qibla position: ${pos.latitude}, ${pos.longitude} (±${pos.accuracy}m)',
      );
    } catch (e) {
      debugPrint('⚠️ Failed to save cached position: $e');
    }
  }

  void _initializeWebView() {
    // Use platform-native WebView Activity on Android for stability and proper permission handling
    try {
      setState(() {
        _isLoading = true;
        _hasError = false;
      });

      final platform = MethodChannel('jadwalsholat.rasyid/web');
      String qiblaUrl = 'https://qiblafinder.withgoogle.com/';

      platform
          .invokeMethod('openQiblaWeb', {'url': qiblaUrl})
          .then((value) {
            // When native activity is started, we consider WebView handed off
            setState(() {
              _isLoading = false;
            });

            // Start periodic injection of last-known GPS coordinates into the native WebView
            _startPeriodicInjection();
          })
          .catchError((e) {
            setState(() {
              _isLoading = false;
              _hasError = true;
              _errorMessage = 'Gagal membuka Qibla Finder: $e';
            });
          });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = 'Gagal menginisialisasi Qibla Finder: $e';
      });
    }
  }

  void _startPeriodicInjection() {
    _injectTimer?.cancel();
    // Send every 5 seconds while the native WebView is expected to be active
    _injectTimer = Timer.periodic(const Duration(seconds: 5), (Timer t) async {
      try {
        if (_currentPosition == null) return;
        final platform = MethodChannel('jadwalsholat.rasyid/web');
        await platform.invokeMethod('injectLocation', {
          'lat': _currentPosition!.latitude,
          'lon': _currentPosition!.longitude,
          'accuracy': _currentPosition!.accuracy,
          'timestamp': _currentPosition!.timestamp.millisecondsSinceEpoch,
        });
        debugPrint(
          '🔁 Injected location to native WebView: ${_currentPosition!.latitude}, ${_currentPosition!.longitude} (±${_currentPosition!.accuracy}m)',
        );
      } catch (e) {
        debugPrint('⚠️ Failed to inject location: $e');
      }
    });
  }

  void _stopPeriodicInjection() {
    _injectTimer?.cancel();
    _injectTimer = null;
  }

  @override
  void dispose() {
    _stopPeriodicInjection();
    super.dispose();
  }

  Future<void> _injectGPSCoordinates() async {
    if (_controller == null || _currentPosition == null) return;

    try {
      // Ultra-high precision coordinates
      double lat = _currentPosition!.latitude;
      double lng = _currentPosition!.longitude;
      double accuracy = _currentPosition!.accuracy;

      // JavaScript code to inject GPS coordinates
      String jsCode =
          '''
        (function() {
          console.log('🎯 Flutter GPS Injection Started');
          
          // Override geolocation getCurrentPosition
          if (navigator.geolocation) {
            const originalGetCurrentPosition = navigator.geolocation.getCurrentPosition;
            
            navigator.geolocation.getCurrentPosition = function(success, error, options) {
              console.log('📍 Intercepting geolocation request');
              
              // Create high-precision position object
              const position = {
                coords: {
                  latitude: $lat,
                  longitude: $lng,
                  accuracy: $accuracy,
                  altitude: null,
                  altitudeAccuracy: null,
                  heading: null,
                  speed: null
                },
                timestamp: Date.now()
              };
              
              console.log('📍 Injecting GPS:', position.coords.latitude, position.coords.longitude, '±' + position.coords.accuracy + 'm');
              
              // Call success callback with injected coordinates
              if (success) {
                success(position);
              }
              
              // Notify Flutter
              if (window.FlutterGPS) {
                window.FlutterGPS.postMessage('GPS injected: ' + position.coords.latitude + ', ' + position.coords.longitude + ' (±' + position.coords.accuracy + 'm)');
              }
            };
            
            // Override watchPosition as well
            const originalWatchPosition = navigator.geolocation.watchPosition;
            
            navigator.geolocation.watchPosition = function(success, error, options) {
              console.log('📍 Intercepting watchPosition request');
              
              const position = {
                coords: {
                  latitude: $lat,
                  longitude: $lng,
                  accuracy: $accuracy,
                  altitude: null,
                  altitudeAccuracy: null,
                  heading: null,
                  speed: null
                },
                timestamp: Date.now()
              };
              
              if (success) {
                success(position);
              }
              
              return 1; // Return a fake watch ID
            };
            
            console.log('✅ GPS injection override complete');
            
            // Trigger any existing geolocation requests
            if (window.google && window.google.maps) {
              console.log('🗺️ Google Maps detected, triggering location update');
            }
          }
        })();
      ''';

      await _controller!.runJavaScript(jsCode);

      debugPrint('🎯 GPS JavaScript injection completed');
      debugPrint(
        '📍 Injected coordinates: $lat, $lng (±${accuracy.toStringAsFixed(1)}m)',
      );
    } catch (e) {
      debugPrint('⚠️ GPS injection failed: $e');
    }
  }

  Future<void> _injectCameraPermissions() async {
    if (_controller == null) return;

    try {
      debugPrint('📷 Injecting camera permissions to WebView...');

      // JavaScript code to enable camera access
      String jsCode = '''
        (function() {
          console.log('📷 Flutter Camera Permission Injection Started');
          
          // Override getUserMedia to always succeed
          if (navigator.mediaDevices && navigator.mediaDevices.getUserMedia) {
            const originalGetUserMedia = navigator.mediaDevices.getUserMedia;
            
            navigator.mediaDevices.getUserMedia = function(constraints) {
              console.log('📷 Intercepting getUserMedia request:', constraints);
              
              // For camera access, return original method
              if (constraints && constraints.video) {
                console.log('📷 Camera access requested - allowing');
                return originalGetUserMedia.call(this, constraints);
              }
              
              // For other media, return original method
              return originalGetUserMedia.call(this, constraints);
            };
            
            console.log('✅ Camera permission injection complete');
          }
          
          // Also handle legacy getUserMedia
          if (navigator.getUserMedia) {
            const originalGetUserMedia = navigator.getUserMedia;
            
            navigator.getUserMedia = function(constraints, success, error) {
              console.log('📷 Intercepting legacy getUserMedia:', constraints);
              return originalGetUserMedia.call(this, constraints, success, error);
            };
          }
          
          // Handle webkitGetUserMedia and mozGetUserMedia
          if (navigator.webkitGetUserMedia) {
            const original = navigator.webkitGetUserMedia;
            navigator.webkitGetUserMedia = function(constraints, success, error) {
              console.log('📷 Intercepting webkitGetUserMedia:', constraints);
              return original.call(this, constraints, success, error);
            };
          }
          
          if (navigator.mozGetUserMedia) {
            const original = navigator.mozGetUserMedia;
            navigator.mozGetUserMedia = function(constraints, success, error) {
              console.log('📷 Intercepting mozGetUserMedia:', constraints);
              return original.call(this, constraints, success, error);
            };
          }
        })();
      ''';

      await _controller!.runJavaScript(jsCode);
      debugPrint('✅ Camera permission JavaScript injection completed');
    } catch (e) {
      debugPrint('⚠️ Camera permission injection failed: $e');
    }
  }

  Future<void> _refreshLocation() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    await _getCurrentLocation();
    await _requestCameraPermission();
    _initializeWebView();

    // Re-inject GPS and camera permissions after refresh
    if (_currentPosition != null && _controller != null) {
      await Future.delayed(const Duration(milliseconds: 1000));
      await _injectGPSCoordinates();

      if (_cameraPermissionGranted) {
        await _injectCameraPermissions();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      body: SafeArea(
        child: Stack(
          children: [
            _buildBody(),
            // Floating refresh button
            Positioned(
              top: 16,
              right: 16,
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0xFF2D2D2D),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  onPressed: _refreshLocation,
                  tooltip: 'Refresh GPS',
                ),
              ),
            ),
            // GPS accuracy indicator
            if (_currentPosition != null)
              Positioned(
                top: 16,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2D2D2D).withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(25),
                      border: Border.all(
                        color: _currentPosition!.accuracy <= 3
                            ? Colors.green
                            : _currentPosition!.accuracy <= 10
                            ? Colors.orange
                            : Colors.red,
                        width: 2,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _currentPosition!.accuracy <= 3
                                  ? Icons.gps_fixed
                                  : _currentPosition!.accuracy <= 10
                                  ? Icons.gps_not_fixed
                                  : Icons.gps_off,
                              color: _currentPosition!.accuracy <= 3
                                  ? Colors.green
                                  : _currentPosition!.accuracy <= 10
                                  ? Colors.orange
                                  : Colors.red,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'GPS: ±${_currentPosition!.accuracy.toStringAsFixed(1)}m',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              _cameraPermissionGranted
                                  ? Icons.camera_alt
                                  : Icons.camera_alt_outlined,
                              color: _cameraPermissionGranted
                                  ? Colors.green
                                  : Colors.grey,
                              size: 16,
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_currentPosition!.latitude.toStringAsFixed(6)}, ${_currentPosition!.longitude.toStringAsFixed(6)}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_hasError) {
      return _buildErrorState();
    }

    if (_isLoading) {
      return _buildLoadingState();
    }

    return _buildWebView();
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Terjadi Kesalahan',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'Kesalahan tidak diketahui',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _refreshLocation,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4DB6AC),
                foregroundColor: Colors.white,
              ),
              child: const Text('Coba Lagi'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4DB6AC)),
          ),
          const SizedBox(height: 16),
          const Text(
            'Memuat Google Qibla Finder...',
            style: TextStyle(fontSize: 16, color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(
            _statusMessage,
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
          const SizedBox(height: 8),
          if (_currentPosition != null)
            Column(
              children: [
                Text(
                  'GPS: ±${_currentPosition!.accuracy.toStringAsFixed(1)}m akurasi',
                  style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                ),
                Text(
                  'Menggunakan ${_currentPosition!.accuracy <= 3
                      ? "ULTRA"
                      : _currentPosition!.accuracy <= 10
                      ? "HIGH"
                      : "STANDARD"} precision',
                  style: TextStyle(
                    fontSize: 10,
                    color: _currentPosition!.accuracy <= 3
                        ? Colors.green
                        : Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.gps_fixed,
                color: _currentPosition != null ? Colors.green : Colors.grey,
                size: 16,
              ),
              const SizedBox(width: 4),
              const Text(
                'GPS',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(width: 16),
              Icon(
                _cameraPermissionGranted
                    ? Icons.camera_alt
                    : Icons.camera_alt_outlined,
                color: _cameraPermissionGranted ? Colors.green : Colors.grey,
                size: 16,
              ),
              const SizedBox(width: 4),
              const Text(
                'Camera',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWebView() {
    if (_controller == null) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4DB6AC)),
        ),
      );
    }
    return WebViewWidget(controller: _controller!);
  }
}
