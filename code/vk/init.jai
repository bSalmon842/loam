/*
Project: Loam
File: vk/init.jai
Author: Brock Salmon
Created: 27APR2025
*/

init_vk :: (vk : *Vk, window : Window_Type) {
    check_vk(create_vk_instance(vk, "Test App"), "create_vk_instance failed: ");
    check_vk(create_vk_surface(vk, window), "create_vk_surface failed: ");
    check_vk(get_vk_physical_device(vk), "get_vk_physical_device failed: ");
    check_vk(create_vk_device(vk), "create_vk_devices failed: ");
    check_vk(create_vk_swapchain(vk), "create_vk_swapchain failed: ");

    vkGetDeviceQueue(vk.device, vk.queueFamilyIndices.graphics, 0, *vk.graphicsQueue);
    
    allocatorCreateInfo := VmaAllocatorCreateInfo.{ .BUFFER_DEVICE_ADDRESS_BIT, vk.physicalDevice, vk.device, 0, null, null, null, null, vk.instance, VK_API_VERSION_1_3, null };
    vmaCreateAllocator(*allocatorCreateInfo, *vk.allocator);

    // Make Draw Image
    // TODO: Make Depth Image
    drawImageExtent := VkExtent2D.{ cast(u32) windowWidth, cast(u32) windowHeight };
    vk.drawImage = create_vk_image(vk, drawImageExtent, .R16G16B16A16_SFLOAT, .TRANSFER_DST_BIT | .TRANSFER_SRC_BIT | .STORAGE_BIT | .COLOR_ATTACHMENT_BIT);

    cmdPoolCreateInfo := VkCommandPoolCreateInfo.{.COMMAND_POOL_CREATE_INFO, null, .RESET_COMMAND_BUFFER_BIT, vk.queueFamilyIndices.graphics};
    fenceCreateInfo := VkFenceCreateInfo.{ .FENCE_CREATE_INFO, null, .SIGNALED_BIT };
    semaphoreCreateInfo := VkSemaphoreCreateInfo.{};
    frameRatios := PoolSizeRatio.[
	.{ .STORAGE_IMAGE, 3 },
	.{ .STORAGE_BUFFER, 3 },
	.{ .UNIFORM_BUFFER, 3 },
	.{ .COMBINED_IMAGE_SAMPLER, 4 },
    ];
    
    for * vk.frames {
	check_vk(vkCreateCommandPool(vk.device, *cmdPoolCreateInfo, null, *it.cmdPool), tprint("Failed to create Command Pool for Frame %", it_index));

	cmdBufferAllocInfo := VkCommandBufferAllocateInfo.{ .COMMAND_BUFFER_ALLOCATE_INFO, null, it.cmdPool, .PRIMARY, 1 };
	check_vk(vkAllocateCommandBuffers(vk.device, *cmdBufferAllocInfo, *it.cmdBuffer), tprint("Failed to create Command Buffer for Frame %", it_index));

	check_vk(vkCreateSemaphore(vk.device, *semaphoreCreateInfo, null, *it.swapSemaphore), tprint("Failed to create Swap Semaphore for Frame %", it_index));
	check_vk(vkCreateSemaphore(vk.device, *semaphoreCreateInfo, null, *it.renderSemaphore), tprint("Failed to create Render Semaphore for Frame %", it_index));
	check_vk(vkCreateFence(vk.device, *fenceCreateInfo, null, *it.renderFence), tprint("Failed to create Render Fence for Frame %", it_index));

	dynamic_descriptor_pool_allocator_init(*it.descriptors, vk.device, 1000, frameRatios);
    }

    // Immediate Submit
    check_vk(vkCreateCommandPool(vk.device, *cmdPoolCreateInfo, null, *vk.immCmdPool), "Failed to create Command Pool for Immediate Submit");
    immCmdBufferAllocInfo := VkCommandBufferAllocateInfo.{ .COMMAND_BUFFER_ALLOCATE_INFO, null, vk.immCmdPool, .PRIMARY, 1 };
    check_vk(vkAllocateCommandBuffers(vk.device, *immCmdBufferAllocInfo, *vk.immCmdBuffer), "Failed to allocate Command Buffer for Immediate Submit");
    
    check_vk(vkCreateFence(vk.device, *fenceCreateInfo, null, *vk.immFence), "Failed to create fence for Immediate Submit");

    // Descriptors
    {
	bindings : DescriptorSetBindings;
	add_binding(*bindings, 0, .COMBINED_IMAGE_SAMPLER);
	vk.singleTextureDescriptorLayout = create_descriptor_set_layout(*bindings, vk.device, .FRAGMENT_BIT);
    }
    
    init_pipelines(vk);

    // Create a temp mesh
    rectVertices := Vertex.[
	.{ position=.{  0.75, -0.75, 0 }, uv=.{ 1, 0 } },
	.{ position=.{  0.75,  0.75, 0 }, uv=.{ 1, 1 } },
	.{ position=.{ -0.75, -0.75, 0 }, uv=.{ 0, 0 } },
	.{ position=.{ -0.75,  0.75, 0 }, uv=.{ 0, 1 } },
    ];
    rectIndices := u32.[0, 1, 2,
		        2, 1, 3];

    vk.testRect = upload_mesh(vk, rectIndices, rectVertices);

    // Write error checkerboard texture
    pixels : [256] u32;
    for * pixels {
        it.* = cast(u32) ifx (it_index % 2 == (ifx it_index % 32 >= 16 then 1 else 0)) then 0xFFFF00FF else 0xFF000000;
    }
    vk.errorCheckerboard = create_vk_image_from_data(vk, pixels.data, VkExtent2D.{ 16, 16 }, .R8G8B8A8_UNORM, .SAMPLED_BIT | .TRANSFER_DST_BIT);

    samplerCreateInfo : VkSamplerCreateInfo;

    samplerCreateInfo.minFilter = .NEAREST;
    samplerCreateInfo.magFilter = .NEAREST;
    vkCreateSampler(vk.device, *samplerCreateInfo, null, *vk.defaultSampler_Nearest);

    samplerCreateInfo.minFilter = .LINEAR;
    samplerCreateInfo.magFilter = .LINEAR;
    vkCreateSampler(vk.device, *samplerCreateInfo, null, *vk.defaultSampler_Linear);
}

create_vk_instance :: (vk : *Vk, appName : string) -> VkResult {
    array_add(*vk.instanceExtensions, VK_KHR_SURFACE_EXTENSION_NAME.data);
    array_add(*vk.instanceExtensions, VK_KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME.data);

    // Make list of extensions to request for each OS we support
    #if OS == .WINDOWS {
	array_add(*vk.instanceExtensions, VK_KHR_WIN32_SURFACE_EXTENSION_NAME.data);
    } else #if OS == .LINUX {
	array_add(*vk.instanceExtensions, VK_KHR_XLIB_SURFACE_EXTENSION_NAME.data);
    } else #if OS == .ANDROID {
	array_add(*vk.instanceExtensions, VK_KHR_ANDROID_SURFACE_EXTENSION_NAME.data);
    }

    // Get supported extensions
    extCount : u32;
    vkEnumerateInstanceExtensionProperties(null, *extCount, null);
    supportedExtensions := NewArray(extCount, VkExtensionProperties);
    defer free(supportedExtensions.data);
    vkEnumerateInstanceExtensionProperties(null, *extCount, supportedExtensions.data);

    // Setup Application and Creation Info
    appInfo : VkApplicationInfo;
    appInfo.pApplicationName = to_c_string(appName);
    appInfo.pEngineName = "Loam";
    appInfo.apiVersion = VK_API_VERSION_1_3;

    createInfo : VkInstanceCreateInfo;
    createInfo.pApplicationInfo = *appInfo;
    
    #if IS_DEBUG {
	for supportedExtensions {
	    ext := from_array_cstr(it.extensionName);
	    if ext == VK_EXT_DEBUG_UTILS_EXTENSION_NAME {
		array_add(*vk.instanceExtensions, VK_EXT_DEBUG_UTILS_EXTENSION_NAME.data);
		break;
	    }
	}

	debugUtilsCreateInfo : VkDebugUtilsMessengerCreateInfoEXT;
	debugUtilsCreateInfo.messageSeverity = .WARNING_BIT_EXT | .ERROR_BIT_EXT;
	debugUtilsCreateInfo.messageType = .GENERAL_BIT_EXT | .VALIDATION_BIT_EXT;
	debugUtilsCreateInfo.pfnUserCallback = vk_debug_callback;
	
	debugUtilsCreateInfo.pNext = createInfo.pNext;
	createInfo.pNext = *debugUtilsCreateInfo;
    }

    if vk.instanceExtensions.count {
	createInfo.enabledExtensionCount = cast(u32) vk.instanceExtensions.count;
	createInfo.ppEnabledExtensionNames = vk.instanceExtensions.data;
    }

    layerCount : u32;
    vkEnumerateInstanceLayerProperties(*layerCount, null);
    supportedLayers := NewArray(layerCount, VkLayerProperties);
    defer free(supportedLayers.data);
    vkEnumerateInstanceLayerProperties(*layerCount, supportedLayers.data);
    
    #if IS_DEBUG {
	validationLayerName := "VK_LAYER_KHRONOS_validation";
	for supportedLayers {
    	    layer := from_array_cstr(it.layerName);
	    if compare(layer, validationLayerName) == 0 {
		createInfo.enabledLayerCount = 1;
		createInfo.ppEnabledLayerNames = *validationLayerName.data;
		break;
	    }
	}

	if createInfo.enabledLayerCount == 0 then log(.WARN, "Failed to find validation layer.");
    }

    return vkCreateInstance(*createInfo, null, *vk.instance);
}

create_vk_surface :: (vk : *Vk, window : Window_Type) -> VkResult {
    #if OS == .WINDOWS {
	surfaceCreateInfo := VkWin32SurfaceCreateInfoKHR.{ hinstance = Windows.GetModuleHandleW(null), hwnd = window };
	return vkCreateWin32SurfaceKHR(vk.instance, *surfaceCreateInfo, null, *vk.surface);
    } else #if OS == .LINUX {
	surfaceCreateInfo := VkXlibSurfaceCreateInfoKHR.{ display = X11.x_global_display, window = window};
	return vkCreateXlibSurfaceKHR(vk.instance, *surfaceCreateInfo, null, *vk.surface);
    } else #if OS == .ANDROID {
	surfaceCreateInfo := VkAndroidSurfaceCreateInfoKHR.{ window = window };
	return vkCreateAndroidSurfaceKHR(vk.instance, *surfaceCreateInfo, null, *vk.surface);
    }
    
    return .ERROR_INITIALIZATION_FAILED;
}

get_vk_physical_device :: (vk : *Vk) -> VkResult {
    array_add(*vk.deviceExtensions, VK_KHR_SWAPCHAIN_EXTENSION_NAME.data);

    vk.reqFeatures_1_0.shaderInt64 = 1;
    vk.reqFeatures_1_2.bufferDeviceAddress = 1;
    vk.reqFeatures_1_2.descriptorIndexing = 1;
    vk.reqFeatures_1_3.dynamicRendering = 1;
    vk.reqFeatures_1_3.synchronization2 = 1;
    
    gpuCount : u32;
    vkEnumeratePhysicalDevices(vk.instance, *gpuCount, null);
    if gpuCount == 0 then return .ERROR_DEVICE_LOST;
    availableDevices := NewArray(gpuCount, VkPhysicalDevice);
    defer free(availableDevices.data);
    check_vk(vkEnumeratePhysicalDevices(vk.instance, *gpuCount, availableDevices.data), "Failed to enumerate physical devices.");

    vk.physicalDevice = find_best_gpu_for_conditions(vk, availableDevices);
    if !vk.physicalDevice {
	log_vk(.FATAL, "Failed to find a valid GPU.");
    }
    
    deviceProperties : VkPhysicalDeviceProperties;
    vkGetPhysicalDeviceProperties(vk.physicalDevice, *deviceProperties);

    log_vk(.SUCCESS, tprint("GPU Selected: %", cast(string) deviceProperties.deviceName));
    
    return .SUCCESS;
}

create_vk_device :: (vk : *Vk) -> VkResult {
    queueCreateInfos : [..] VkDeviceQueueCreateInfo;
    array_add(*queueCreateInfos, queue_create_info(vk.queueFamilyIndices.graphics));
    if vk.queueFamilyIndices.compute != vk.queueFamilyIndices.graphics {
	    array_add(*queueCreateInfos, queue_create_info(vk.queueFamilyIndices.compute));
    }

    if vk.enableVkVideo {
	if vk.queueFamilyIndices.videoDecode != vk.queueFamilyIndices.graphics &&
	   vk.queueFamilyIndices.videoDecode != vk.queueFamilyIndices.compute {
	    array_add(*queueCreateInfos, queue_create_info(vk.queueFamilyIndices.videoDecode));
	}
    }
    
    deviceCreateInfo := VkDeviceCreateInfo.{};
    deviceCreateInfo.queueCreateInfoCount = cast(u32) queueCreateInfos.count;
    deviceCreateInfo.pQueueCreateInfos = queueCreateInfos.data;

    // NOTE: We've already checked these features and extensions are available when creating the physical device
    featureChain := chain_physical_device_features(*vk.reqFeatures_1_1, *vk.reqFeatures_1_2, *vk.reqFeatures_1_3);
    featureChain.features = vk.reqFeatures_1_0;
    deviceCreateInfo.pNext = *featureChain;

    deviceCreateInfo.enabledExtensionCount = cast(u32) vk.deviceExtensions.count;
    deviceCreateInfo.ppEnabledExtensionNames = vk.deviceExtensions.data;
    
    return vkCreateDevice(vk.physicalDevice, *deviceCreateInfo, null, *vk.device);
}

create_vk_swapchain :: (vk : *Vk) -> VkResult #must {
    oldSwapchain := vk.swapchain;

    surfaceCaps : VkSurfaceCapabilitiesKHR;
    check_vk(vkGetPhysicalDeviceSurfaceCapabilitiesKHR(vk.physicalDevice, vk.surface, *surfaceCaps), "Failed to get surface capabilities");

    // Set swapchain extent
    vk.swapchainExtent = surfaceCaps.currentExtent;
    if vk.swapchainExtent.width == U32_MAX || vk.swapchainExtent.height == U32_MAX {
	vk.swapchainExtent.width  = cast(u32) clamp(windowWidth, surfaceCaps.minImageExtent.width, surfaceCaps.maxImageExtent.width);
	vk.swapchainExtent.height = cast(u32) clamp(windowHeight, surfaceCaps.minImageExtent.height, surfaceCaps.maxImageExtent.height);
    }

    // Get best present mode for our purposes
    presentModeCount : u32;
    check_vk(vkGetPhysicalDeviceSurfacePresentModesKHR(vk.physicalDevice, vk.surface, *presentModeCount, null), "Failed to get valid present modes for the current surface from the physical device");
    if presentModeCount == 0 {
	log_vk(.FATAL, "No present modes found for surface, this goes against the Vulkan spec as not even FIFO was found.");
	return .ERROR_SURFACE_LOST_KHR;
    }
    presentModes := NewArray(presentModeCount, VkPresentModeKHR);
    defer free(presentModes.data);
    check_vk(vkGetPhysicalDeviceSurfacePresentModesKHR(vk.physicalDevice, vk.surface, *presentModeCount, presentModes.data), "Failed to get valid present modes for the current surface from the physical device");

    selectedPresentMode := VkPresentModeKHR.FIFO_KHR;

    // TODO: Get this from a setting struct of some kind, we should probably also force vsync on android (I don't think there's any reason not to)
    vsync :: false;
    if !vsync {
	for presentModes {
	    if it == .MAILBOX_KHR {
		selectedPresentMode = it;
		break;
	    } else if it == .IMMEDIATE_KHR {
		selectedPresentMode = it;
	    }
	}
    }

    // Get Image count
    swapchainImageCount := surfaceCaps.minImageCount + 1;
    if surfaceCaps.maxImageCount > 0 && swapchainImageCount > surfaceCaps.maxImageCount {
	swapchainImageCount := surfaceCaps.maxImageCount;
    }

    // Get the basic transform for the surface if it exists
    preTransform := surfaceCaps.currentTransform;
    if surfaceCaps.supportedTransforms & .IDENTITY_BIT_KHR then preTransform = .IDENTITY_BIT_KHR;

    // Get the best alpha composition for the window (because not all devices support Alpha Opaque
    windowCompositeAlpha := VkCompositeAlphaFlagBitsKHR.OPAQUE_BIT_KHR;
    compositeAlphaFlags := VkCompositeAlphaFlagBitsKHR.[ .OPAQUE_BIT_KHR, .PRE_MULTIPLIED_BIT_KHR, .POST_MULTIPLIED_BIT_KHR, .INHERIT_BIT_KHR ];
    for compositeAlphaFlags {
	if surfaceCaps.supportedCompositeAlpha & it {
	    windowCompositeAlpha = it;
	    break;
	}
    }

    // Get colour format and colour space
    formatCount : u32;
    check_vk(vkGetPhysicalDeviceSurfaceFormatsKHR(vk.physicalDevice, vk.surface, *formatCount, null), "Failed to get supported surface formats");
    if formatCount == 0 {
	log_vk(.FATAL, "No formats found for surface.");
	return .ERROR_SURFACE_LOST_KHR;
    }
    surfaceFormats := NewArray(formatCount, VkSurfaceFormatKHR);
    defer free(surfaceFormats.data);
    check_vk(vkGetPhysicalDeviceSurfaceFormatsKHR(vk.physicalDevice, vk.surface, *formatCount, surfaceFormats.data), "Failed to get supported surface formats");

    selectedFormat := surfaceFormats[0];
    preferredFormats := VkFormat.[ .R8G8B8A8_UNORM, .B8G8R8A8_UNORM ];
    for supportedFormat : surfaceFormats {
	for preferredFormats {
	    if supportedFormat.format == it && supportedFormat.colorSpace == .COLOR_SPACE_SRGB_NONLINEAR_KHR {
		selectedFormat = supportedFormat;
		break supportedFormat;
	    }
	}
    }

    colourFormat := selectedFormat.format;
    colourSpace := selectedFormat.colorSpace;
    
    // Get supported usage flags we want
    // TODO: Do we want to error if we don't at least get the dest bit?
    usageFlags := VkImageUsageFlags.COLOR_ATTACHMENT_BIT;
    if surfaceCaps.supportedUsageFlags & .TRANSFER_SRC_BIT then usageFlags |= .TRANSFER_SRC_BIT;
    if surfaceCaps.supportedUsageFlags & .TRANSFER_DST_BIT then usageFlags |= .TRANSFER_DST_BIT;
    
    createInfo := VkSwapchainCreateInfoKHR.{ .SWAPCHAIN_CREATE_INFO_KHR, null, 0,
	vk.surface, swapchainImageCount, colourFormat, colourSpace, .{ vk.swapchainExtent.width, vk.swapchainExtent.height }, 1, usageFlags, .EXCLUSIVE,
	0, null, preTransform, windowCompositeAlpha, selectedPresentMode, VK_TRUE, oldSwapchain };
    check_vk(vkCreateSwapchainKHR(vk.device, *createInfo, null, *vk.swapchain), "Failed to create swapchain");

    vk.swapchainFormat = colourFormat;

    log_vk(.INFO, "Created Swapchain");
    log_vk(.INFO, tprint("Swapchain Extent: %", vk.swapchainExtent));
    log_vk(.INFO, tprint("Swapchain Present Mode: %", selectedPresentMode));
    log_vk(.INFO, tprint("Swapchain Image Count: %", swapchainImageCount));
    log_vk(.INFO, tprint("Swapchain Transform: %", preTransform));
    log_vk(.INFO, tprint("Swapchain Composite Alpha: %", windowCompositeAlpha));
    log_vk(.INFO, tprint("Swapchain Colour Format: %", colourFormat));
    log_vk(.INFO, tprint("Swapchain Colour Space: %", colourSpace));
    log_vk(.INFO, tprint("Swapchain Usage Flags: %", usageFlags));

    // Clear out the old swapchain
    // NOTE: We don't need to destroy the images because they're owned by the swapchain itself
    if oldSwapchain {
	for * vk.swapchainImageViews {
	    vkDestroyImageView(vk.device, it.*, null);
	}
	vkDestroySwapchainKHR(vk.device, oldSwapchain, null);
    }

    imageCount : u32;
    check_vk(vkGetSwapchainImagesKHR(vk.device, vk.swapchain, *imageCount, null), "Failed to get images from swapchain");
    array_resize(*vk.swapchainImages, imageCount);
    check_vk(vkGetSwapchainImagesKHR(vk.device, vk.swapchain, *imageCount, vk.swapchainImages.data), "Failed to get images from swapchain");

    array_resize(*vk.swapchainImageViews, imageCount);
    for 0 .. imageCount-1 {
	imgViewCreateInfo : VkImageViewCreateInfo;
	imgViewCreateInfo.image = vk.swapchainImages[it];
	imgViewCreateInfo.viewType = ._2D;
	imgViewCreateInfo.format = colourFormat;
	imgViewCreateInfo.components = .{ .R, .G, .B, .A };
	imgViewCreateInfo.subresourceRange = .{ .COLOR_BIT, 0, 1, 0, 1 };
	check_vk(vkCreateImageView(vk.device, *imgViewCreateInfo, null, *vk.swapchainImageViews[it]), tprint("Failed to create image view for swapchain image: %", it));
    }
    
    return .SUCCESS;
}

resize_swapchain :: (vk : *Vk) {
    vkDeviceWaitIdle(vk.device);
    check_vk(create_vk_swapchain(vk), "Failed to recreate swapchain when reizing window");
    vk.resizeRequested = false;
}

init_pipelines :: (vk : *Vk) {
    // Mesh Pipeline
    vertShader := load_shader_module(vk.device, MESH_VERTEX_SHADER);
    fragShader := load_shader_module(vk.device, MESH_FRAGMENT_SHADER);

    bufferRange := VkPushConstantRange.{ .VERTEX_BIT, 0, size_of(MeshPushConstants) };
    layout := VkPipelineLayoutCreateInfo.{ .PIPELINE_LAYOUT_CREATE_INFO, null, 0, 1, *vk.singleTextureDescriptorLayout, 1, *bufferRange };
    check_vk(vkCreatePipelineLayout(vk.device, *layout, null, *vk.meshPipelineLayout), "Failed to create pipeline layout for test triangle");

    builder : GraphicsPipelineInfo;
    builder.layout = vk.meshPipelineLayout;

    set_pipeline_shaders(*builder, vertShader, fragShader);
    set_pipeline_input_topology(*builder, .TRIANGLE_LIST);
    set_pipeline_polygon_mode(*builder, .FILL);
    set_pipeline_cull_mode(*builder, .NONE, .CLOCKWISE);
    set_pipeline_multisampling_mode(*builder, .None);
    set_pipeline_blending_mode(*builder, false);
    set_pipeline_colour_attachment_format(*builder, vk.drawImage.format);
    set_pipeline_depth_format(*builder, .UNDEFINED);

    vk.meshPipeline = build_graphics_pipeline(vk, *builder);

    vkDestroyShaderModule(vk.device, vertShader, null);
    vkDestroyShaderModule(vk.device, fragShader, null);
}
