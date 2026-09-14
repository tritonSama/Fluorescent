#include <jni.h>
#include <android/hardware_buffer_jni.h>
#include <android/log.h>
#include <vulkan/vulkan.h>
#include "../../src/fluorescent_vulkan.h"

#define LOG_TAG "FluorescentVulkan"
#define ALOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define ALOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

extern "C" JNIEXPORT jlong JNICALL
Java_com_fluorescent_vulkan_FluorescentVulkanPlugin_createHardwareBuffer(JNIEnv *env, jobject thiz, jint width, jint height) {
    AHardwareBuffer_Desc desc = {};
    desc.width = width;
    desc.height = height;
    desc.layers = 1;
    desc.format = AHARDWAREBUFFER_FORMAT_R8G8B8A8_UNORM;
    desc.usage = AHARDWAREBUFFER_USAGE_GPU_SAMPLED_IMAGE | AHARDWAREBUFFER_USAGE_GPU_COLOR_OUTPUT;

    AHardwareBuffer *buffer = nullptr;
    int result = AHardwareBuffer_allocate(&desc, &buffer);
    if (result != 0) {
        ALOGE("Failed to allocate AHardwareBuffer.");
        return 0;
    }
    ALOGI("AHardwareBuffer allocated successfully.");
    return reinterpret_cast<jlong>(buffer);
}

extern "C" JNIEXPORT void JNICALL
Java_com_fluorescent_vulkan_FluorescentVulkanPlugin_destroyHardwareBuffer(JNIEnv *env, jobject thiz, jlong bufferPtr) {
    if (bufferPtr != 0) {
        AHardwareBuffer *buffer = reinterpret_cast<AHardwareBuffer *>(bufferPtr);
        AHardwareBuffer_release(buffer);
        ALOGI("AHardwareBuffer released.");
    }
}
