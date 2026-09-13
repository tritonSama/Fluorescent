# Technical Spike Plan: Texture Interop Path

## Objective
Establish a zero-copy path for rendering 3D content (via Vulkan, Metal, or WebGPU) directly into Flutter's rendering pipeline so that the `FluorescentViewport` can display 3D content efficiently within a Flame game.

## Challenges
1. **Platform Differences**: Each platform uses different graphics APIs (Vulkan for Android/Linux, Metal for iOS/macOS, WebGPU for the Web).
2. **Flutter Texture Widget**: Flutter allows embedding foreign textures using the `Texture` widget or via engine-level APIs, but the mechanism varies by platform.
3. **Synchronization**: Synchronizing the rendering of the 3D scene with Flutter's rasterization thread to avoid tearing and hitches.

## Proposed Steps

### Step 1: Research Flutter's Foreign Texture APIs
- Investigate `TextureRegistry` and how to register external textures in Flutter on iOS and Android.
- Understand the difference between `SurfaceTexture` (Android) and `CVPixelBuffer` (iOS) in the context of Flutter's `Texture` widget.

### Step 2: Implement Platform-Specific Texture Creation
#### Android (Vulkan)
- Use JNI/NDK to create a Vulkan instance and device.
- Allocate a Vulkan image and bind it to an Android `HardwareBuffer`.
- Pass the `HardwareBuffer` to Flutter via a `SurfaceTexture`.

#### iOS/macOS (Metal)
- Use Objective-C++ or Swift to create a Metal device and command queue.
- Allocate an `MTLTexture` backed by an `IOSurface` or `CVPixelBuffer`.
- Register the buffer with Flutter's `TextureRegistry`.

#### Web (WebGPU)
- Investigate `OffscreenCanvas` and WebGPU.
- Render to an `ImageBitmap` and bridge it to Flutter Web's texture abstraction.

### Step 3: Implement the Dart Bridge
- Create FFI bindings (for mobile/desktop) and JS interop (for web) to communicate with the native renderers.
- Define a unified Dart interface for requesting a texture, resizing it, and notifying Flutter when a new frame is ready.

### Step 4: Integrate with FluorescentViewport
- Modify `FluorescentViewport` to use a Flutter `Texture` widget instead of a simple `Canvas.drawRect`.
- Ensure the viewport respects the position, size, and transform applied by the Flame component hierarchy.

### Step 5: Prototype and Benchmark
- Implement a basic rotating cube in native code.
- Measure frame times, GPU memory usage, and battery impact.
- Identify bottlenecks in the texture transfer process (e.g., CPU readbacks, format conversions).
