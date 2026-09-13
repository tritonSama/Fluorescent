# Fluorescent

Fluorescent is a 3D rendering bridge for the Flame engine, enabling AAA-quality open world games within Flutter's ecosystem. It wraps Flame (preserving 2D maturity) and renders via Vulkan/Metal/WebGPU into Flutter's texture pipeline.

## Core Philosophy: Extend, don't replace
Fluorescent is an extension for Flame rather than a replacement, adding AAA 3D capabilities while preserving Flame's 2D maturity and Flutter integration. It embeds into Flame as a `FluorescentViewport` component, providing rendering capabilities for 3D worlds.

## Core Architecture: The Onion Model

```
┌─────────────────────────────────────────┐
│           Fluorite (HMI Shell)          │
│    Safety-certified compositor only     │
├─────────────────────────────────────────┤
│      Fluorescent 3D Bridge (New)        │
│   Vulkan/WebGPU scene → Flutter texture │
├─────────────────────────────────────────┤
│      Flame Engine (Unmodified)          │
│   2D games, UI, input, audio, lifecycle │
│   [Existing ecosystem 100% compatible]  │
├─────────────────────────────────────────┤
│      Flutter (Platform glue)            │
│   Widgets, platform channels, stores    │
└─────────────────────────────────────────┘
```

## Packages
The project is split into several packages:
- `fluorescent_core`: Platform-agnostic logic (scene graph, abstract render API, math, streaming)
- `fluorescent_flame`: Flame integration (`FluorescentViewport` component)
- `fluorescent_vulkan`: Vulkan backend for Android/Linux
- `fluorescent_metal`: Metal backend for iOS/macOS
- `fluorescent_webgpu`: WebGPU backend for Web
- `fluorescent_fluorite`: Automotive adapter integration

For more details on the architecture, see [docs/architecture.md](docs/architecture.md).
