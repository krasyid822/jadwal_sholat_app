// Simple stub for registering an iframe view for the Qibla finder.
// A proper web implementation should register a platform view factory that
// returns an IFrameElement. Keep this file as a no-op to avoid analyzer
// errors on non-web targets and to be safe during web builds when the
// platform view registration is handled elsewhere.
void registerQiblaIFrame(String viewType, String url) {
  // No-op stub. Implement web-only registration in a separate
  // conditional-imported file if you want an actual embedded iframe.
}
