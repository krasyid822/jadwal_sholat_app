Windows location capability

Why: On Windows desktop, apps packaged as MSIX/Appx may require explicit manifest capabilities for hardware location access. Some hosts may honor DeviceCapability alone, others require the uap:Capability declaration.

What we added:
- In `windows/runner/Package.appxmanifest` we added both:
  - `<DeviceCapability Name="location" />`
  - `<uap:Capability Name="location" />`

How to verify:
1. When packaging as MSIX/Appx, ensure the manifest included in the package is the updated `Package.appxmanifest` from the runner folder.
2. Build the installer and install on Windows. Then open Settings > Privacy & security > Location and verify the app appears and is allowed to access location.

Notes:
- During development (running from `flutter run`), some location flows may still be limited by the host OS and developer environment.
- If you rely on WinRT APIs, ensure the `permission_handler_windows` plugin is up-to-date.

Fallbacks:
- If hardware GPS is unavailable or denied, the app will attempt to use approximate location (browser IP-based or system-derived coarse location), or a cached location saved earlier.

If you'd like, I can also add a small script to help you build an MSIX with the updated manifest.
