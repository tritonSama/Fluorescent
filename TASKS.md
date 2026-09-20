# Fluorite AAA Engine - Tasks

## Phase 2: Functional Test App & Geofencing (In Progress)

### 1. Functional Test App Setup [DONE]
- [x] Create a new Flutter application (`functional_test_app`).
- [x] Set up `google_maps_flutter` for the base map rendering.
- [x] Integrate the `fluorite_core` FFI bridge to initialize the native engine.

### 2. Live Social Map & Geofencing [PARTIAL]
- [ ] Implement a custom map tile provider for Slippy Map tiles.
- [x] Add real-time driver location markers.
- [x] Implement the Geofencing visual layer (event zones, speed traps).
- [ ] Connect map enter/exit events to the Rust `NavigationServer` or `PhysicsServer` for logical processing.

### 3. Background Location Tracking [DONE]
- [x] Integrate a background location tracking package (e.g., `flutter_background_geolocation` or a custom platform channel implementation).
- [x] Ensure battery-efficient GPS sampling (adaptive update rate).

### 4. Multiplayer Sync (Rust Core) [TODO]
- [ ] Implement a WebSocket or WebRTC data-channel server within the Rust networking foundation.
- [ ] Implement client-side position interpolation and extrapolation (to handle 30 Hz ping limits).
- [ ] Build the entity culling logic to only render/process drivers within a visible radius.

### 5. Social Feed [DONE]
- [x] Build the Flutter UI layer for a social feed (club posts, recent activities).
- [x] Build basic DMs/group channel UI.
- [x] (Backend integration points left open for Firebase/Stream integration later).

## Phase 3: AAA Engine Features (Pending)

### 1. GPU-Driven Rendering & Virtual Geometry
- Implement compute shader-based culling (frustum, occlusion).
- Develop virtual geometry system (Nanite-style micro-polygon rendering).
- Transition to unified GPU command buffers to minimize CPU submission overhead.

### 2. Advanced Lighting (Dynamic GI & Virtual Shadows)
- Implement screen-space or hardware-accelerated raytraced Dynamic Global Illumination.
- Build Virtual Shadow Maps (VSM) for high-resolution, scalable shadow rendering.
- Integrate temporal upscaling techniques (TAA, FSR2) into the render graph.

### 3. GPU VFX & Particles
- Build a node-based GPU particle simulation framework.
- Enable high-count particle rendering (Niagara-style) interacting with the depth/GBuffer.

### 4. Advanced Animation & Destruction
- Implement runtime bone/skeletal IK constraints and state machines in the Rust engine.
- Integrate physics-driven destruction (Chaos-style chunk separation and rigid body spawning).

### 5. World Streaming & PCG
- Implement spatial hashing and chunked world streaming for open-world scales.
- Develop Procedural Content Generation (PCG) frameworks for terrain generation, vegetation placement, and biome mapping.

## Phase 4: Online Features (Upcoming)

### 1. Multiplayer Core
- Implement replication, prediction, and rollback networking architecture.
- Ensure state synchronization between authoritative game runtime (Rust) and client runtime.

### 2. Dedicated Server & Matchmaking
- Enable headless server deployments using Rust server binary.
- Implement session-based matchmaking logic.

### 3. Identity and Cloud Integrations
- Integrate backend identity management and accounts.
- Persistent player profiles and data storage.
