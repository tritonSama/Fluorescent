# Fluorite AAA Engine - Tasks

## Phase 2: Functional Test App & Geofencing

### 1. Functional Test App Setup
- Create a new Flutter application (`functional_test_app`).
- Set up `google_maps_flutter` for the base map rendering.
- Integrate the `fluorite_core` FFI bridge to initialize the native engine.

### 2. Live Social Map & Geofencing
- Implement a custom map tile provider for Slippy Map tiles.
- Add real-time driver location markers.
- Implement the Geofencing visual layer (event zones, speed traps).
- Connect map enter/exit events to the Rust `NavigationServer` or `PhysicsServer` for logical processing.

### 3. Background Location Tracking
- Integrate a background location tracking package (e.g., `flutter_background_geolocation` or a custom platform channel implementation).
- Ensure battery-efficient GPS sampling (adaptive update rate).

### 4. Multiplayer Sync (Rust Core)
- Implement a WebSocket or WebRTC data-channel server within the Rust networking foundation.
- Implement client-side position interpolation and extrapolation (to handle 30 Hz ping limits).
- Build the entity culling logic to only render/process drivers within a visible radius.

### 5. Social Feed
- Build the Flutter UI layer for a social feed (club posts, recent activities).
- Build basic DMs/group channel UI.
- (Backend integration points left open for Firebase/Stream integration later).
