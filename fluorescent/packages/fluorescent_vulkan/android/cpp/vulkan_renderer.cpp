#include <jni.h>
#include <android/hardware_buffer_jni.h>
#include <android/log.h>
#include <vulkan/vulkan.h>
#include <vulkan/vulkan_android.h>
#include "../../src/fluorescent_vulkan.h"
#include "../../src/model_loader.h"

#define LOG_TAG "FluorescentVulkanAndroid"
#define ALOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define ALOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

static VkImage g_ahb_image = VK_NULL_HANDLE;
static VkDeviceMemory g_ahb_memory = VK_NULL_HANDLE;
static VkImageView g_ahb_image_view = VK_NULL_HANDLE;
static VkFramebuffer g_framebuffer = VK_NULL_HANDLE;

static uint32_t g_fb_width = 0;
static uint32_t g_fb_height = 0;

void bind_hardware_buffer_to_vulkan(AHardwareBuffer* buffer) {
    VkDevice device = get_vulkan_device();
    if (device == VK_NULL_HANDLE) {
        ALOGE("Cannot bind buffer: Vulkan device is not initialized.");
        return;
    }

    AHardwareBuffer_Desc desc;
    AHardwareBuffer_describe(buffer, &desc);
    g_fb_width = desc.width;
    g_fb_height = desc.height;

    VkAndroidHardwareBufferPropertiesANDROID ahbProperties{};
    ahbProperties.sType = VK_STRUCTURE_TYPE_ANDROID_HARDWARE_BUFFER_PROPERTIES_ANDROID;
    auto vkGetAndroidHardwareBufferPropertiesANDROID = 
         (PFN_vkGetAndroidHardwareBufferPropertiesANDROID)vkGetDeviceProcAddr(device, "vkGetAndroidHardwareBufferPropertiesANDROID");

    if (vkGetAndroidHardwareBufferPropertiesANDROID != nullptr) {
         if (vkGetAndroidHardwareBufferPropertiesANDROID(device, buffer, &ahbProperties) != VK_SUCCESS) {
             ALOGE("Failed to get AHardwareBuffer properties.");
             return;
         }
    } else {
         ALOGE("vkGetAndroidHardwareBufferPropertiesANDROID not found.");
         return;
    }

    VkExternalMemoryImageCreateInfo externalInfo{};
    externalInfo.sType = VK_STRUCTURE_TYPE_EXTERNAL_MEMORY_IMAGE_CREATE_INFO;
    externalInfo.handleTypes = VK_EXTERNAL_MEMORY_HANDLE_TYPE_ANDROID_HARDWARE_BUFFER_BIT_ANDROID;

    VkImageCreateInfo imageInfo{};
    imageInfo.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
    imageInfo.pNext = &externalInfo;
    imageInfo.imageType = VK_IMAGE_TYPE_2D;
    imageInfo.format = VK_FORMAT_R8G8B8A8_UNORM;
    imageInfo.extent.width = desc.width;
    imageInfo.extent.height = desc.height;
    imageInfo.extent.depth = 1;
    imageInfo.mipLevels = 1;
    imageInfo.arrayLayers = 1;
    imageInfo.samples = VK_SAMPLE_COUNT_1_BIT;
    imageInfo.tiling = VK_IMAGE_TILING_OPTIMAL;
    imageInfo.usage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_SAMPLED_BIT;
    imageInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    imageInfo.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;

    if (vkCreateImage(device, &imageInfo, nullptr, &g_ahb_image) != VK_SUCCESS) {
        ALOGE("Failed to create Vulkan Image from AHardwareBuffer.");
        return;
    }

    VkImportAndroidHardwareBufferInfoANDROID importInfo{};
    importInfo.sType = VK_STRUCTURE_TYPE_IMPORT_ANDROID_HARDWARE_BUFFER_INFO_ANDROID;
    importInfo.buffer = buffer;

    VkMemoryAllocateInfo allocInfo{};
    allocInfo.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    allocInfo.pNext = &importInfo;
    allocInfo.allocationSize = ahbProperties.allocationSize;
    allocInfo.memoryTypeIndex = ahbProperties.memoryTypeBits; // Simplified lookup

    if (vkAllocateMemory(device, &allocInfo, nullptr, &g_ahb_memory) != VK_SUCCESS) {
        ALOGE("Failed to allocate memory for AHardwareBuffer Image.");
        return;
    }

    vkBindImageMemory(device, g_ahb_image, g_ahb_memory, 0);

    // Create Image View
    VkImageViewCreateInfo viewInfo{};
    viewInfo.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
    viewInfo.image = g_ahb_image;
    viewInfo.viewType = VK_IMAGE_VIEW_TYPE_2D;
    viewInfo.format = VK_FORMAT_R8G8B8A8_UNORM;
    viewInfo.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    viewInfo.subresourceRange.baseMipLevel = 0;
    viewInfo.subresourceRange.levelCount = 1;
    viewInfo.subresourceRange.baseArrayLayer = 0;
    viewInfo.subresourceRange.layerCount = 1;

    if (vkCreateImageView(device, &viewInfo, nullptr, &g_ahb_image_view) != VK_SUCCESS) {
        ALOGE("Failed to create Image View.");
        return;
    }

    // Create Framebuffer
    VkRenderPass renderPass = get_vulkan_render_pass();
    VkFramebufferCreateInfo framebufferInfo{};
    framebufferInfo.sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO;
    framebufferInfo.renderPass = renderPass;
    framebufferInfo.attachmentCount = 1;
    framebufferInfo.pAttachments = &g_ahb_image_view;
    framebufferInfo.width = desc.width;
    framebufferInfo.height = desc.height;
    framebufferInfo.layers = 1;

    if (vkCreateFramebuffer(device, &framebufferInfo, nullptr, &g_framebuffer) != VK_SUCCESS) {
        ALOGE("Failed to create Framebuffer.");
        return;
    }

    ALOGI("HardwareBuffer bound to Framebuffer successfully.");
}

void android_render_frame() {
    VkDevice device = get_vulkan_device();
    VkRenderPass renderPass = get_vulkan_render_pass();
    VkPipeline pipeline = get_vulkan_graphics_pipeline();
    VkPipelineLayout pipelineLayout = get_vulkan_pipeline_layout();
    VkDescriptorSet descriptorSet = get_vulkan_descriptor_set();
    VkCommandPool commandPool = get_vulkan_command_pool();
    VkQueue graphicsQueue = get_vulkan_graphics_queue();

    if (!device || !renderPass || !pipeline || !g_framebuffer) {
        ALOGE("Cannot render frame: Pipeline or Framebuffer missing.");
        return;
    }

    VkCommandBufferAllocateInfo allocInfo{};
    allocInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    allocInfo.commandPool = commandPool;
    allocInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    allocInfo.commandBufferCount = 1;

    VkCommandBuffer commandBuffer;
    vkAllocateCommandBuffers(device, &allocInfo, &commandBuffer);

    VkCommandBufferBeginInfo beginInfo{};
    beginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    beginInfo.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    
    vkBeginCommandBuffer(commandBuffer, &beginInfo);

    VkRenderPassBeginInfo renderPassInfo{};
    renderPassInfo.sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;
    renderPassInfo.renderPass = renderPass;
    renderPassInfo.framebuffer = g_framebuffer;
    renderPassInfo.renderArea.offset = {0, 0};
    renderPassInfo.renderArea.extent = {g_fb_width, g_fb_height};

    VkClearValue clearColor = {{{0.1f, 0.1f, 0.1f, 1.0f}}};
    renderPassInfo.clearValueCount = 1;
    renderPassInfo.pClearValues = &clearColor;

    vkCmdBeginRenderPass(commandBuffer, &renderPassInfo, VK_SUBPASS_CONTENTS_INLINE);
    vkCmdBindPipeline(commandBuffer, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline);

    VkViewport viewport{};
    viewport.x = 0.0f;
    viewport.y = 0.0f;
    viewport.width = static_cast<float>(g_fb_width);
    viewport.height = static_cast<float>(g_fb_height);
    viewport.minDepth = 0.0f;
    viewport.maxDepth = 1.0f;
    vkCmdSetViewport(commandBuffer, 0, 1, &viewport);

    VkRect2D scissor{};
    scissor.offset = {0, 0};
    scissor.extent = {g_fb_width, g_fb_height};
    vkCmdSetScissor(commandBuffer, 0, 1, &scissor);

    vkCmdBindDescriptorSets(commandBuffer, VK_PIPELINE_BIND_POINT_GRAPHICS, pipelineLayout, 0, 1, &descriptorSet, 0, nullptr);

    // Draw the 3 vertices defining our basic triangle
    vkCmdDraw(commandBuffer, 3, 1, 0, 0);

    vkCmdEndRenderPass(commandBuffer);
    if (vkEndCommandBuffer(commandBuffer) != VK_SUCCESS) {
        ALOGE("Failed to record command buffer!");
        return;
    }

    VkSubmitInfo submitInfo{};
    submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    submitInfo.commandBufferCount = 1;
    submitInfo.pCommandBuffers = &commandBuffer;

    vkQueueSubmit(graphicsQueue, 1, &submitInfo, VK_NULL_HANDLE);
    vkQueueWaitIdle(graphicsQueue);
    
    vkFreeCommandBuffers(device, commandPool, 1, &commandBuffer);
    ALOGI("Android Vulkan: Render frame completed with vkCmdDraw.");
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_fluorescent_vulkan_FluorescentVulkanPlugin_createHardwareBuffer(JNIEnv *env, jobject thiz, jint width, jint height) {
    if (!init_vulkan() || !init_vulkan_device()) {
        ALOGE("Failed to initialize Vulkan core from Android.");
        return 0;
    }

    init_graphics_pipeline();

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
    
    bind_hardware_buffer_to_vulkan(buffer);
    android_render_frame();

    return reinterpret_cast<jlong>(buffer);
}

extern "C" JNIEXPORT void JNICALL
Java_com_fluorescent_vulkan_FluorescentVulkanPlugin_destroyHardwareBuffer(JNIEnv *env, jobject thiz, jlong bufferPtr) {
    VkDevice device = get_vulkan_device();
    if (g_framebuffer != VK_NULL_HANDLE) {
        vkDestroyFramebuffer(device, g_framebuffer, nullptr);
        g_framebuffer = VK_NULL_HANDLE;
    }
    if (g_ahb_image_view != VK_NULL_HANDLE) {
        vkDestroyImageView(device, g_ahb_image_view, nullptr);
        g_ahb_image_view = VK_NULL_HANDLE;
    }
    if (g_ahb_image != VK_NULL_HANDLE) {
        vkDestroyImage(device, g_ahb_image, nullptr);
        g_ahb_image = VK_NULL_HANDLE;
    }
    if (g_ahb_memory != VK_NULL_HANDLE) {
        vkFreeMemory(device, g_ahb_memory, nullptr);
        g_ahb_memory = VK_NULL_HANDLE;
    }

    if (bufferPtr != 0) {
        AHardwareBuffer *buffer = reinterpret_cast<AHardwareBuffer *>(bufferPtr);
        AHardwareBuffer_release(buffer);
        ALOGI("AHardwareBuffer released.");
    }
}
