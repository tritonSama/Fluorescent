#include "fluorescent_vulkan.h"
#include <vulkan/vulkan.h>
#include <iostream>
#include <vector>
#include "shaders.h"

#ifdef __ANDROID__
#include <android/log.h>
#define LOG_TAG "FluorescentVulkanCore"
#define ALOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define ALOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#else
#define ALOGI(...) std::cout << "FluorescentVulkanCore: " << __VA_ARGS__ << std::endl
#define ALOGE(...) std::cerr << "FluorescentVulkanCore ERROR: " << __VA_ARGS__ << std::endl
#endif

// Global Vulkan state for this simplistic implementation
static VkInstance g_instance = VK_NULL_HANDLE;
static VkPhysicalDevice g_physical_device = VK_NULL_HANDLE;
static VkDevice g_device = VK_NULL_HANDLE;
static VkQueue g_graphics_queue = VK_NULL_HANDLE;

static VkShaderModule g_vertex_shader = VK_NULL_HANDLE;
static VkShaderModule g_fragment_shader = VK_NULL_HANDLE;
static VkPipelineLayout g_pipeline_layout = VK_NULL_HANDLE;
static VkPipeline g_graphics_pipeline = VK_NULL_HANDLE;
static VkRenderPass g_render_pass = VK_NULL_HANDLE;
static VkCommandPool g_command_pool = VK_NULL_HANDLE;
static VkCommandBuffer g_command_buffer = VK_NULL_HANDLE;

bool init_vulkan() {
    if (g_instance != VK_NULL_HANDLE) {
        return true;
    }

    VkApplicationInfo appInfo{};
    appInfo.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    appInfo.pApplicationName = "Fluorescent Engine";
    appInfo.applicationVersion = VK_MAKE_VERSION(1, 0, 0);
    appInfo.pEngineName = "Fluorescent";
    appInfo.engineVersion = VK_MAKE_VERSION(1, 0, 0);
    appInfo.apiVersion = VK_API_VERSION_1_1;

    std::vector<const char*> extensions;
    extensions.push_back(VK_KHR_SURFACE_EXTENSION_NAME);
#ifdef __ANDROID__
    extensions.push_back("VK_KHR_android_surface");
    extensions.push_back(VK_KHR_EXTERNAL_MEMORY_CAPABILITIES_EXTENSION_NAME);
#endif

    VkInstanceCreateInfo createInfo{};
    createInfo.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    createInfo.pApplicationInfo = &appInfo;
    createInfo.enabledExtensionCount = static_cast<uint32_t>(extensions.size());
    createInfo.ppEnabledExtensionNames = extensions.data();
    createInfo.enabledLayerCount = 0;

    if (vkCreateInstance(&createInfo, nullptr, &g_instance) != VK_SUCCESS) {
        ALOGE("Failed to create Vulkan instance!");
        return false;
    }
    ALOGI("Vulkan Instance created successfully.");
    return true;
}

bool init_vulkan_device() {
    if (g_instance == VK_NULL_HANDLE) {
        ALOGE("Cannot initialize device without Vulkan instance.");
        return false;
    }

    uint32_t deviceCount = 0;
    vkEnumeratePhysicalDevices(g_instance, &deviceCount, nullptr);
    if (deviceCount == 0) {
        ALOGE("Failed to find GPUs with Vulkan support!");
        return false;
    }
    std::vector<VkPhysicalDevice> devices(deviceCount);
    vkEnumeratePhysicalDevices(g_instance, &deviceCount, devices.data());
    g_physical_device = devices[0];

    uint32_t queueFamilyCount = 0;
    vkGetPhysicalDeviceQueueFamilyProperties(g_physical_device, &queueFamilyCount, nullptr);
    std::vector<VkQueueFamilyProperties> queueFamilies(queueFamilyCount);
    vkGetPhysicalDeviceQueueFamilyProperties(g_physical_device, &queueFamilyCount, queueFamilies.data());

    int graphicsQueueFamilyIndex = -1;
    for (uint32_t i = 0; i < queueFamilyCount; ++i) {
        if (queueFamilies[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) {
            graphicsQueueFamilyIndex = i;
            break;
        }
    }
    if (graphicsQueueFamilyIndex == -1) {
        ALOGE("Failed to find a suitable queue family!");
        return false;
    }

    VkDeviceQueueCreateInfo queueCreateInfo{};
    queueCreateInfo.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
    queueCreateInfo.queueFamilyIndex = graphicsQueueFamilyIndex;
    queueCreateInfo.queueCount = 1;
    float queuePriority = 1.0f;
    queueCreateInfo.pQueuePriorities = &queuePriority;

    VkPhysicalDeviceFeatures deviceFeatures{};

    std::vector<const char*> deviceExtensions;
#ifdef __ANDROID__
    deviceExtensions.push_back("VK_ANDROID_external_memory_android_hardware_buffer");
    deviceExtensions.push_back(VK_KHR_SAMPLER_YCBCR_CONVERSION_EXTENSION_NAME);
    deviceExtensions.push_back(VK_KHR_EXTERNAL_MEMORY_EXTENSION_NAME);
    deviceExtensions.push_back(VK_EXT_QUEUE_FAMILY_FOREIGN_EXTENSION_NAME);
    deviceExtensions.push_back(VK_KHR_DEDICATED_ALLOCATION_EXTENSION_NAME);
    deviceExtensions.push_back(VK_KHR_GET_MEMORY_REQUIREMENTS_2_EXTENSION_NAME);
    deviceExtensions.push_back(VK_KHR_BIND_MEMORY_2_EXTENSION_NAME);
#endif

    VkDeviceCreateInfo createInfo{};
    createInfo.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
    createInfo.pQueueCreateInfos = &queueCreateInfo;
    createInfo.queueCreateInfoCount = 1;
    createInfo.pEnabledFeatures = &deviceFeatures;
    createInfo.enabledExtensionCount = static_cast<uint32_t>(deviceExtensions.size());
    createInfo.ppEnabledExtensionNames = deviceExtensions.data();

    if (vkCreateDevice(g_physical_device, &createInfo, nullptr, &g_device) != VK_SUCCESS) {
        ALOGE("Failed to create logical device!");
        return false;
    }
    vkGetDeviceQueue(g_device, graphicsQueueFamilyIndex, 0, &g_graphics_queue);

    VkCommandPoolCreateInfo poolInfo{};
    poolInfo.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
    poolInfo.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    poolInfo.queueFamilyIndex = graphicsQueueFamilyIndex;
    if (vkCreateCommandPool(g_device, &poolInfo, nullptr, &g_command_pool) != VK_SUCCESS) {
        ALOGE("Failed to create command pool!");
        return false;
    }

    VkCommandBufferAllocateInfo allocInfo{};
    allocInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    allocInfo.commandPool = g_command_pool;
    allocInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    allocInfo.commandBufferCount = 1;

    if (vkAllocateCommandBuffers(g_device, &allocInfo, &g_command_buffer) != VK_SUCCESS) {
        ALOGE("Failed to allocate command buffers!");
        return false;
    }

    ALOGI("Vulkan Logical Device and Graphics Queue created successfully.");
    return true;
}

VkShaderModule create_shader_module(const uint32_t* code, size_t size) {
    VkShaderModuleCreateInfo createInfo{};
    createInfo.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
    createInfo.codeSize = size;
    createInfo.pCode = code;

    VkShaderModule shaderModule;
    if (vkCreateShaderModule(g_device, &createInfo, nullptr, &shaderModule) != VK_SUCCESS) {
        ALOGE("Failed to create shader module!");
        return VK_NULL_HANDLE;
    }
    return shaderModule;
}

bool init_graphics_pipeline() {
    if (g_device == VK_NULL_HANDLE) {
        ALOGE("Cannot initialize pipeline without Vulkan device.");
        return false;
    }

    g_vertex_shader = create_shader_module(VERTEX_SHADER, sizeof(VERTEX_SHADER));
    g_fragment_shader = create_shader_module(FRAGMENT_SHADER, sizeof(FRAGMENT_SHADER));

    VkPipelineShaderStageCreateInfo vertShaderStageInfo{};
    vertShaderStageInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    vertShaderStageInfo.stage = VK_SHADER_STAGE_VERTEX_BIT;
    vertShaderStageInfo.module = g_vertex_shader;
    vertShaderStageInfo.pName = "main";

    VkPipelineShaderStageCreateInfo fragShaderStageInfo{};
    fragShaderStageInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    fragShaderStageInfo.stage = VK_SHADER_STAGE_FRAGMENT_BIT;
    fragShaderStageInfo.module = g_fragment_shader;
    fragShaderStageInfo.pName = "main";

    VkPipelineShaderStageCreateInfo shaderStages[] = {vertShaderStageInfo, fragShaderStageInfo};

    VkPipelineVertexInputStateCreateInfo vertexInputInfo{};
    vertexInputInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;

    VkPipelineInputAssemblyStateCreateInfo inputAssembly{};
    inputAssembly.sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO;
    inputAssembly.topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;

    VkPipelineViewportStateCreateInfo viewportState{};
    viewportState.sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO;
    viewportState.viewportCount = 1;
    viewportState.scissorCount = 1;

    VkPipelineRasterizationStateCreateInfo rasterizer{};
    rasterizer.sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO;
    rasterizer.polygonMode = VK_POLYGON_MODE_FILL;
    rasterizer.lineWidth = 1.0f;
    rasterizer.cullMode = VK_CULL_MODE_BACK_BIT;
    rasterizer.frontFace = VK_FRONT_FACE_CLOCKWISE;

    VkPipelineMultisampleStateCreateInfo multisampling{};
    multisampling.sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;
    multisampling.rasterizationSamples = VK_SAMPLE_COUNT_1_BIT;

    VkPipelineColorBlendAttachmentState colorBlendAttachment{};
    colorBlendAttachment.colorWriteMask = VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT | VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT;
    colorBlendAttachment.blendEnable = VK_FALSE;

    VkPipelineColorBlendStateCreateInfo colorBlending{};
    colorBlending.sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO;
    colorBlending.attachmentCount = 1;
    colorBlending.pAttachments = &colorBlendAttachment;

    VkPipelineLayoutCreateInfo pipelineLayoutInfo{};
    pipelineLayoutInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;

    if (vkCreatePipelineLayout(g_device, &pipelineLayoutInfo, nullptr, &g_pipeline_layout) != VK_SUCCESS) {
        ALOGE("Failed to create pipeline layout!");
        return false;
    }

    VkAttachmentDescription colorAttachment{};
    colorAttachment.format = VK_FORMAT_R8G8B8A8_UNORM;
    colorAttachment.samples = VK_SAMPLE_COUNT_1_BIT;
    colorAttachment.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR;
    colorAttachment.storeOp = VK_ATTACHMENT_STORE_OP_STORE;
    colorAttachment.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
    colorAttachment.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
    colorAttachment.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    colorAttachment.finalLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;

    VkAttachmentReference colorAttachmentRef{};
    colorAttachmentRef.attachment = 0;
    colorAttachmentRef.layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;

    VkSubpassDescription subpass{};
    subpass.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS;
    subpass.colorAttachmentCount = 1;
    subpass.pColorAttachments = &colorAttachmentRef;

    VkRenderPassCreateInfo renderPassInfo{};
    renderPassInfo.sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO;
    renderPassInfo.attachmentCount = 1;
    renderPassInfo.pAttachments = &colorAttachment;
    renderPassInfo.subpassCount = 1;
    renderPassInfo.pSubpasses = &subpass;

    if (vkCreateRenderPass(g_device, &renderPassInfo, nullptr, &g_render_pass) != VK_SUCCESS) {
        ALOGE("Failed to create render pass!");
        return false;
    }

    // Usually you would call vkCreateGraphicsPipelines here, but to avoid immense boilerplate
    // for dynamic viewports/framebuffers in this stub, we acknowledge the layout and pass are ready.
    ALOGI("Vulkan Graphics Pipeline Layout and Render Pass initialized.");
    return true;
}

void render_frame() {
    if (g_device == VK_NULL_HANDLE || g_command_buffer == VK_NULL_HANDLE) return;

    VkCommandBufferBeginInfo beginInfo{};
    beginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;

    if (vkBeginCommandBuffer(g_command_buffer, &beginInfo) != VK_SUCCESS) {
        ALOGE("Failed to begin recording command buffer!");
        return;
    }

    // In a real scenario we'd bind the framebuffer from the AHardwareBuffer here
    // vkCmdBeginRenderPass(g_command_buffer, &renderPassInfo, VK_SUBPASS_CONTENTS_INLINE);
    // vkCmdBindPipeline(g_command_buffer, VK_PIPELINE_BIND_POINT_GRAPHICS, g_graphics_pipeline);
    // vkCmdDraw(g_command_buffer, 3, 1, 0, 0);
    // vkCmdEndRenderPass(g_command_buffer);

    if (vkEndCommandBuffer(g_command_buffer) != VK_SUCCESS) {
        ALOGE("Failed to record command buffer!");
        return;
    }

    VkSubmitInfo submitInfo{};
    submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    submitInfo.commandBufferCount = 1;
    submitInfo.pCommandBuffers = &g_command_buffer;

    vkQueueSubmit(g_graphics_queue, 1, &submitInfo, VK_NULL_HANDLE);
    vkQueueWaitIdle(g_graphics_queue);

    ALOGI("Render frame executed.");
}

void cleanup_vulkan() {
    if (g_device != VK_NULL_HANDLE) {
        vkDestroyRenderPass(g_device, g_render_pass, nullptr);
        vkDestroyPipelineLayout(g_device, g_pipeline_layout, nullptr);
        vkDestroyShaderModule(g_device, g_fragment_shader, nullptr);
        vkDestroyShaderModule(g_device, g_vertex_shader, nullptr);
        vkDestroyCommandPool(g_device, g_command_pool, nullptr);
        vkDestroyDevice(g_device, nullptr);
        g_device = VK_NULL_HANDLE;
    }
    if (g_instance != VK_NULL_HANDLE) {
        vkDestroyInstance(g_instance, nullptr);
        g_instance = VK_NULL_HANDLE;
    }
    ALOGI("Fluorescent Vulkan: Cleaned up.");
}

VkDevice get_vulkan_device() {
    return g_device;
}

VkPhysicalDevice get_vulkan_physical_device() {
    return g_physical_device;
}

static float g_view_proj_matrix[16] = {
    1.0f, 0.0f, 0.0f, 0.0f,
    0.0f, 1.0f, 0.0f, 0.0f,
    0.0f, 0.0f, 1.0f, 0.0f,
    0.0f, 0.0f, 0.0f, 1.0f
};

extern "C" void update_camera(const float* view_proj_matrix) {
    if (view_proj_matrix != nullptr) {
        for (int i = 0; i < 16; ++i) {
            g_view_proj_matrix[i] = view_proj_matrix[i];
        }
        // In a real pipeline, this would copy data to a Uniform Buffer Object (UBO)
        ALOGI("Camera View-Projection Matrix updated.");
    }
}
