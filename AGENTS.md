# Agent Roles

To effectively implement this complex architecture, we define the following agent roles for concurrent multi-agent execution:

1. **Rendering Architect Agent**: Focuses on the core graphics pipeline, including the Vulkan/Metal bindings, the Render Graph, and Shader Toolchain (Phase 2 and Phase 3 features like dynamic quality tiers and GPU VFX).
2. **Systems Programmer Agent**: Responsible for the underlying Rust core foundation, ECS, memory management, and `flutter_rust_bridge` zero-copy communication.
3. **Gameplay/Simulation Agent**: Implements the Physics, Navigation, Animation, and Procedural Content Generation (PCG) systems.
4. **Networking & Cloud Agent**: Handles Phase 4 requirements, including multiplayer replication, rollback, dedicated server logic, and cloud integrations (e.g., Firebase, OpenRouteService for mapping).
5. **Tools & Editor Agent**: Develops the Flutter-based Editor UI, Visual Scripting, Profiler, and Asset Pipeline tooling (Phase 5).
6. **UI/UX & Mobile Integration Agent**: Focuses on Flutter UI application layers, including social feeds, background location tracking, battery-efficient GPS, and push notifications.
