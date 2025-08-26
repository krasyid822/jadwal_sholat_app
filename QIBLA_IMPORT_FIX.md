# Fix Import Error - QiblaScreenSimple

## Issue Fixed
- **Error**: `GoogleQiblaWebViewScreen` isn't a class
- **Location**: `qibla_screen_simple.dart` line 377
- **Cause**: Import reference ke class yang tidak ada

## Solution Applied

### 1. Import Fix
```dart
// Before (Error)
import 'google_qibla_webview_screen.dart';

// After (Fixed)
import 'google_qibla_finder_screen.dart';
```

### 2. Class Reference Fix
```dart
// Before (Error)
children: [_buildLocalCompass(), const GoogleQiblaWebViewScreen()],

// After (Fixed)  
children: [_buildLocalCompass(), const GoogleQiblaFinderScreen()],
```

## Root Cause
During the restoration of GoogleQiblaFinderScreen, the file `google_qibla_webview_screen.dart` was created as a simple wrapper, but `qibla_screen_simple.dart` was still trying to reference a non-existent class `GoogleQiblaWebViewScreen`.

## Impact
- ✅ Import error resolved
- ✅ TabBarView now correctly references GoogleQiblaFinderScreen
- ✅ Enhanced Google Qibla Finder (no AppBar + high-precision GPS) now accessible from QiblaScreenSimple tabs
- ✅ `flutter analyze` shows no issues

## Files Modified
- `lib/screens/qibla_screen_simple.dart` - Fixed import dan class reference

## Integration Status
QiblaScreenSimple now properly integrates with the enhanced GoogleQiblaFinderScreen yang features:
- No AppBar (immersive experience)
- High-precision GPS injection
- Floating UI controls
- Real-time GPS accuracy indicator

## Testing
- ✅ `flutter analyze`: No issues found
- ✅ Build process: Running successfully
- ✅ Import resolution: Fixed
