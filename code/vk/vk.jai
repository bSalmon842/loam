/*
Project: Loam
File: vk.jai
Author: Brock Salmon
Created: 11JUN2025
*/

FRAMES_IN_FLIGHT :: 2;

Vk :: struct {
    // Requested options
    instanceExtensions : [..] *u8;
    deviceExtensions : [..] *u8;
    
    reqFeatures_1_0 : VkPhysicalDeviceFeatures;
    reqFeatures_1_1 : VkPhysicalDeviceVulkan11Features;
    reqFeatures_1_2 : VkPhysicalDeviceVulkan12Features;
    reqFeatures_1_3 : VkPhysicalDeviceVulkan13Features;

    // Base Vulkan structs
    instance : VkInstance;
    surface : VkSurfaceKHR;
    physicalDevice : VkPhysicalDevice;
    device : VkDevice;
    swapchain : VkSwapchainKHR;

    swapchainImages : [..] VkImage;
    swapchainImageViews : [..] VkImageView;
    swapchainExtent : VkExtent2D;
    swapchainFormat : VkFormat;
    resizeRequested : bool;

    allocator : VmaAllocator;

    textureFormat : VkFormat;	

    currentFrame : u64;
    frames : [FRAMES_IN_FLIGHT] FrameCommandInfo;

    drawImageExtent : VkExtent2D;
    drawImage : AllocatedImageInfo;
    
    graphicsQueue : VkQueue;

    QueueFamilyIndices :: struct {
	// NOTE: We don't store a transfer queue index, as graphics and compute queue families include the same capabilities
	graphics    : u32;
	compute     : u32;
	videoDecode : u32;
    }
    queueFamilyIndices : QueueFamilyIndices;

    // Immediate Submit
    immFence     : VkFence;
    immCmdBuffer : VkCommandBuffer;
    immCmdPool   : VkCommandPool;
    ///////////////////

    // Pipelines
    meshPipeline       : VkPipeline;
    meshPipelineLayout : VkPipelineLayout;

    // Sampler for each member of VkFilter (we don't care about CUBIC)
    defaultSampler_Nearest : VkSampler;
    defaultSampler_Linear  : VkSampler;

    // Built in error texture
    errorCheckerboard : AllocatedImageInfo;
    testTexture : AllocatedImageInfo;
    
    singleTextureDescriptorLayout : VkDescriptorSetLayout;
    
    testRect : MeshBuffers;

    // Optional Stuff
    enableVkVideo : bool;
}

FrameCommandInfo :: struct {
    cmdPool : VkCommandPool;
    cmdBuffer : VkCommandBuffer;
    
    swapSemaphore : VkSemaphore;
    renderSemaphore : VkSemaphore;
    renderFence : VkFence;

    descriptors : DynamicDescriptorPoolAllocator;
}

AllocatedImageInfo :: struct {
    image  : VkImage;
    view   : VkImageView;
    extent : VkExtent2D;
    format : VkFormat;

    allocation : VmaAllocation;
}

AllocatedBufferInfo :: struct {
    buffer         : VkBuffer;
    allocation     : VmaAllocation;
    allocationInfo : VmaAllocationInfo;
}


#load "descriptors.jai";
#load "init.jai";
#load "mesh.jai";
#load "pipelines.jai";
#load "render.jai";
#load "shaders.jai";
#load "util.jai";
