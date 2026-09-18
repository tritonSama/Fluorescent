# Agent: UI/UX & Mobile Integration

**Focus**: Flutter UI application layers, social feeds, location tracking.

## Context
We have scaffolded the `functional_test_app` in `fluorescent/examples/functional_test_app` which features a `google_maps_flutter` implementation and stubbed out geofencing logic crossing over an FFI boundary to `fluorite_core`. We are currently working through Phase 2.

## Tasks
1. **Background Location Tracking**: Integrate a background location tracking package (e.g. `flutter_background_geolocation` or similar). Make sure that the GPS sampling adapts based on battery efficiency.
2. **Social Feed**: Build the Flutter UI layer for a social feed, club posts, and recent activities. Build basic DMs/group channel UI.

Ensure to update any relevant documentation such as `PROJECT.md` and verify changes with tests when complete.
