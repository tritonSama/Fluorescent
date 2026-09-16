# Fluorescent Agent Assignments

This document outlines the assigned agent personas for each phase of the Fluorescent project, drawing architectural inspiration from Godot (Server pattern) and O3DE (Atom renderer / ECS).

## Phase 1: Core Bridge (Months 1-3)
**Agent:** Architecture & Integration Agent (Godot Server Pattern Specialist)
**Role:** Establish the `RenderingServer` and `PhysicsServer` singletons, ensuring the core bridge between Flame and the native 3D viewport functions asynchronously without blocking the main isolate.

## Phase 2: Rendering Features (Months 4-6)
**Agent:** Graphics Pipeline Agent (O3DE Atom Specialist)
**Role:** Implement the clustered forward+ renderer, virtual shadow maps, and mesh shaders. This agent will focus on the data-driven render graph and RHI (Render Hardware Interface) abstractions.

## Phase 3: Streaming & Physics (Months 7-9)
**Agent:** ECS & Systems Agent (O3DE Entity-Component Specialist)
**Role:** Build the chunk streaming system and integrate Jolt Physics using an Entity-Component System approach for the 3D world representations, bridging cleanly with Flame's 2D components.

## Phase 4: Platform Expansion (Months 10-12)
**Agent:** Platform & Safety Agent (Fluorite Automotive Specialist)
**Role:** Implement WebGPU fallbacks and ensure the automotive adapter meets memory constraints and safety process isolations.

## Phase 5: Ecosystem (Months 13-15)
**Agent:** Tooling & DX Agent (Godot Editor Specialist)
**Role:** Develop the asset pipeline CLI, shader hot-reload, and visual node editors, focusing on a rapid iterative developer experience akin to the Godot Editor.
