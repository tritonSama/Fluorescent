# Higgsfield Bridge for Fluorescent

This tool provides a bridge to integrate **Higgsfield AI** generative models directly into the Fluorescent content pipeline. 

## Purpose
Fluorescent requires highly optimized 3D assets and textures. The `higgsfield_api.py` script acts as a middleware that allows developers (or the engine's asset build pipeline) to programmatically request textures and 3D meshes using generative prompts, and then automatically route them into the Fluorescent chunk streaming and LOD generation pipeline.

## Usage (Stub)
Currently, this is a stub. In the future, this module will handle API authentication, asynchronous generation requests, and automatic asset format conversion (e.g., pulling a texture from Higgsfield and compressing it to ASTC for Vulkan mobile rendering).
