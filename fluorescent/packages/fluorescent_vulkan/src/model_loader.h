#ifndef MODEL_LOADER_H
#define MODEL_LOADER_H

#include <vector>
#include <string>
#include <stdint.h>
#include <stdbool.h>

#ifdef _WIN32
#define EXPORT __declspec(dllexport)
#else
#define EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Loads a glTF model from a file path. Returns true on success.
EXPORT bool load_gltf_model(const char* filepath);

#ifdef __cplusplus
}
#endif

// A simple structure to represent a vertex
struct Vertex {
    float position[3];
    float normal[3];
    float uv[2];
};

// Represents a loaded 3D Mesh
struct Mesh {
    std::vector<Vertex> vertices;
    std::vector<uint32_t> indices;
};

// Function accessible in C++ to load a model and return its mesh data
bool parse_gltf(const std::string& filepath, std::vector<Mesh>& outMeshes);

#endif // MODEL_LOADER_H
