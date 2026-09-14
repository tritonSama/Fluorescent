# WebGPU Integration Roadmap

## Objective
To provide hardware-accelerated 3D web rendering for Fluorescent using WebGPU, acting as a fallback for platforms where native Vulkan or Metal are unavailable, particularly within PWA contexts.

## Architectural Alignment
The `fluorescent_webgpu` package will serve as the bridge between Flutter Web and WebGPU.

### Phase 1: WebGPU Viewport (Immediate)
*   **Native 3D Viewport**: Embed a hardware-accelerated canvas via `HtmlElementView` connected to `ui_web.platformViewRegistry`.
*   **WebGPU Bridge**: Utilize a JavaScript interop bridge (`webgpu_bridge.js`) to initialize the WebGPU context (`navigator.gpu.requestAdapter`) and bind it to the `HtmlElementView`'s canvas.
*   **Flutter Integration**: The `FluorescentViewport` component in Flame will detect the web platform and utilize `fluorescent_webgpu` to mount the HTML view instead of relying on native FFI textures.

### Future Phases
*   **Phase 2: glTF & Animation**: Extend the WebGPU pipeline to handle `.glb` parsing and skeletal animation via compute shaders.
*   **Phase 3: PBR & IBL**: Implement Image-Based Lighting and physically based rendering within the WebGPU shaders.
*   **Phase 4: ECS Web Sync**: Connect native ECS state to the WebGPU renderer using Emscripten/WASM for high-performance state synchronization.
