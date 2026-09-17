#include "model_loader.h"
#define CGLTF_IMPLEMENTATION
#include "third_party/cgltf/cgltf.h"
#include <iostream>

#ifdef __ANDROID__
#include <android/log.h>
#define LOG_TAG "FluorescentModelLoader"
#define ALOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define ALOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#else
#define ALOGI(...) std::cout << "FluorescentModelLoader: " << __VA_ARGS__ << std::endl
#define ALOGE(...) std::cerr << "FluorescentModelLoader ERROR: " << __VA_ARGS__ << std::endl
#endif

bool parse_gltf(const std::string& filepath, std::vector<Mesh>& outMeshes) {
    cgltf_options options = {};
    cgltf_data* data = NULL;
    cgltf_result result = cgltf_parse_file(&options, filepath.c_str(), &data);

    if (result != cgltf_result_success) {
        ALOGE("Failed to parse glTF file: %s (Error code: %d)", filepath.c_str(), result);
        return false;
    }

    result = cgltf_load_buffers(&options, data, filepath.c_str());
    if (result != cgltf_result_success) {
        ALOGE("Failed to load glTF buffers for: %s", filepath.c_str());
        cgltf_free(data);
        return false;
    }

    // Very basic parsing: Just extracting position for now to demonstrate structure
    for (cgltf_size i = 0; i < data->meshes_count; ++i) {
        const cgltf_mesh& mesh = data->meshes[i];
        
        for (cgltf_size j = 0; j < mesh.primitives_count; ++j) {
            const cgltf_primitive& primitive = mesh.primitives[j];
            Mesh outMesh;

            // Extract Vertices
            for (cgltf_size k = 0; k < primitive.attributes_count; ++k) {
                const cgltf_attribute& attribute = primitive.attributes[k];
                if (attribute.type == cgltf_attribute_type_position) {
                    cgltf_accessor* accessor = attribute.data;
                    outMesh.vertices.resize(accessor->count);
                    for (cgltf_size v = 0; v < accessor->count; ++v) {
                        cgltf_accessor_read_float(accessor, v, outMesh.vertices[v].position, 3);
                        // Stub normals and UVs for now
                        outMesh.vertices[v].normal[0] = 0.0f;
                        outMesh.vertices[v].normal[1] = 1.0f;
                        outMesh.vertices[v].normal[2] = 0.0f;
                        outMesh.vertices[v].uv[0] = 0.0f;
                        outMesh.vertices[v].uv[1] = 0.0f;
                    }
                }
            }
            
            // Extract Indices
            if (primitive.indices != nullptr) {
                cgltf_accessor* accessor = primitive.indices;
                outMesh.indices.resize(accessor->count);
                for (cgltf_size idx = 0; idx < accessor->count; ++idx) {
                    outMesh.indices[idx] = static_cast<uint32_t>(cgltf_accessor_read_index(accessor, idx));
                }
            }

            outMeshes.push_back(outMesh);
            ALOGI("Loaded a mesh with %zu vertices and %zu indices", outMesh.vertices.size(), outMesh.indices.size());
        }
    }

    cgltf_free(data);
    return true;
}

extern "C" bool load_gltf_model(const char* filepath) {
    if (filepath == nullptr) return false;
    std::vector<Mesh> loadedMeshes;
    return parse_gltf(std::string(filepath), loadedMeshes);
}
