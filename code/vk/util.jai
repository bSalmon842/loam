/*
Project: Loam
File: vk/util.jai
Author: Brock Salmon
Created: 27APR2025
*/

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

    graphicsCmdPool : VkCommandPool;
    graphicsQueue : VkQueue;

    QueueFamilyIndices :: struct {
	// NOTE: We don't store a transfer queue index, as graphics and compute queue families include the same capabilities
	graphics    : u32;
	compute     : u32;
	videoDecode : u32;
    }
    queueFamilyIndices : QueueFamilyIndices;

    SyncStructures :: struct {
	renderSem  : VkSemaphore;
	presentSem : VkSemaphore;
	fences : [..] VkFence;
    }
    sync : SyncStructures;

    submitInfo : VkSubmitInfo;

    // Optional Stuff
    enableVkVideo : bool;
}

find_best_gpu_for_conditions :: (vk : *Vk, availableDevices : [] VkPhysicalDevice) -> VkPhysicalDevice {
    bestGPU : VkPhysicalDevice = null;

    // Filter out invalid physical devices
    validGPUs : [..] VkPhysicalDevice;
    for device : availableDevices {
	deviceProperties : VkPhysicalDeviceProperties;
	vkGetPhysicalDeviceProperties(device, *deviceProperties);
	
	// Check Vulkan 1.3 is supported
	// NOTE: WSL2 doesn't recognise Vulkan 1.3 and the dozen driver will only report 1.2 even if 1.3 is actually supported, so we skip this check for linux.
	if OS != .LINUX && deviceProperties.apiVersion < VK_API_VERSION_1_3 {
	    log_vk(.INFO, tprint("Physical Device: % is not valid due to not meeting the minimum API version, version was: %.%.%", to_string(deviceProperties.deviceName.data),
				 VK_VERSION_MAJOR(deviceProperties.apiVersion), VK_VERSION_MINOR(deviceProperties.apiVersion), VK_VERSION_PATCH(deviceProperties.apiVersion)));
	    continue;
	}

	// Check queue families have the queues we need available
	queueFamilyCount : u32;
	vkGetPhysicalDeviceQueueFamilyProperties(device, *queueFamilyCount, null);
	queueFamilies := NewArray(queueFamilyCount, VkQueueFamilyProperties);
	defer free(queueFamilies.data);
	vkGetPhysicalDeviceQueueFamilyProperties(device, *queueFamilyCount, queueFamilies.data);

	usedIndices : [..] u32;
	if !get_queue_family_index(.GRAPHICS_BIT, queueFamilies, *usedIndices, deviceProperties) {
	    continue;
	}
	if !get_queue_family_index(.COMPUTE_BIT, queueFamilies, *usedIndices, deviceProperties) {
	    continue;
	}
	
	// Check features are available
	// TODO: We probably need a way to establish if a feature is really needed or not.
	features_1_1 : VkPhysicalDeviceVulkan11Features;
	features_1_2 : VkPhysicalDeviceVulkan12Features;
	features_1_3 : VkPhysicalDeviceVulkan13Features;
	featureChain := chain_physical_device_features(*features_1_1, *features_1_2, *features_1_3);
	vkGetPhysicalDeviceFeatures2(device, *featureChain);
	features_1_0 := featureChain.features;

	typeInfos := Type_Info_Struct.[ type_info(VkPhysicalDeviceFeatures), type_info(VkPhysicalDeviceVulkan11Features),
					type_info(VkPhysicalDeviceVulkan12Features), type_info(VkPhysicalDeviceVulkan13Features) ];

	allFeaturesSupported := true;
	for info : typeInfos {
	    infoIndex := it_index;
	    for member : info.members {
		if member.name == "sType" || member.name == "pNext" then continue;

		offset := member.offset_in_bytes;
		get_member_at_offset :: (features : *void) -> VkBool32 #expand {
		    return (cast(*VkBool32) (cast(*u8) features + `offset)).*;
		}

		requested : VkBool32;
		supported : VkBool32;

		if infoIndex == {
		    case 0; {
			requested = get_member_at_offset(*vk.reqFeatures_1_0);
			supported = get_member_at_offset(*features_1_0);
		    }
		    case 1; {
			requested = get_member_at_offset(*vk.reqFeatures_1_1);
			supported = get_member_at_offset(*features_1_1);
		    }
		    case 2; {
			requested = get_member_at_offset(*vk.reqFeatures_1_2);
			supported = get_member_at_offset(*features_1_2);
		    }
		    case 3; {
			requested = get_member_at_offset(*vk.reqFeatures_1_3);
			supported = get_member_at_offset(*features_1_3);
		    }
		    case; assert(false, "Invalid feature struct type info index");
		}

		if requested && !supported {
		    allFeaturesSupported = false;
		    break info;
		}
	    }
	}

	if !allFeaturesSupported {
	    log_vk(.INFO, tprint("Physical Device: % is not valid due to not supporting all requested features", to_string(deviceProperties.deviceName.data)));
	    continue;
	}

	// Check if extensions are available
	extCount : u32;
	vkEnumerateDeviceExtensionProperties(device, null, *extCount, null);
	extensions := NewArray(extCount, VkExtensionProperties);
	defer free(extensions.data);
	vkEnumerateDeviceExtensionProperties(device, null, *extCount, extensions.data);

	allExtensionsSupported := true;
	for vk.deviceExtensions {
	    requested := to_string(it);
	    
	    foundExt := false;
	    for extensions {
		ext := cast(string) it.extensionName;
		ext.count = find_index_from_left(ext, "\0");
		if requested == ext {
		    foundExt = true;
		    break;
		}
	    }
	    
	    if !foundExt {
		allExtensionsSupported = false;
		break;
	    }
	}

	if !allExtensionsSupported {
	    log_vk(.INFO, tprint("Physical Device: % is not valid due to not supporting all requested extensions", to_string(deviceProperties.deviceName.data)));
	    continue;
	}

	array_add(*validGPUs, device);
    }

    // Select a GPU out of the best available options, prefer discrete
    bestScore := 0;
    for validGPUs {
	score := 0;

	// Find what we determine to be the best performing GPU
	properties : VkPhysicalDeviceProperties;
	vkGetPhysicalDeviceProperties(it, *properties);

	memoryKB := properties.limits.maxMemoryAllocationCount * size_of(VkDeviceSize) / 1024;
	print("Memory (KB): %\n\n", memoryKB);
	score += memoryKB;
	
	if score > bestScore {
	    bestScore = score;
	    bestGPU = it;
	}
    }

    if bestGPU {
	deviceProperties : VkPhysicalDeviceProperties;
	vkGetPhysicalDeviceProperties(bestGPU, *deviceProperties);
	
	queueFamilyCount : u32;
	vkGetPhysicalDeviceQueueFamilyProperties(bestGPU, *queueFamilyCount, null);
	queueFamilies := NewArray(queueFamilyCount, VkQueueFamilyProperties);
	defer free(queueFamilies.data);
	vkGetPhysicalDeviceQueueFamilyProperties(bestGPU, *queueFamilyCount, queueFamilies.data);

	// NOTE: We know these all already exist how we want them from the filter stage, so ignore the found result
	usedIndices : [..] u32;
	_, vk.queueFamilyIndices.graphics    = get_queue_family_index(.GRAPHICS_BIT, queueFamilies, *usedIndices, deviceProperties);
	_, vk.queueFamilyIndices.compute     = get_queue_family_index(.COMPUTE_BIT, queueFamilies, *usedIndices, deviceProperties);
	vk.enableVkVideo, vk.queueFamilyIndices.videoDecode = get_queue_family_index(.VIDEO_DECODE_BIT_KHR, queueFamilies, *usedIndices, deviceProperties);
    }
    
    return bestGPU;
}

get_dedicated_queue_family_index :: (flag : VkQueueFlags, queueFamilies : [] VkQueueFamilyProperties, usedIndices : *[..] u32) -> bool #must, u32 {
    bestIndex := U32_MAX;
    
    for queueFamilies {
	index := cast(u32) it_index;
	if (flag & it.queueFlags) == flag {
	    bestIndex = index;
	    if !is_in_array(index, usedIndices.*) {
		array_add(usedIndices, index);
		return true, index;
	    }
	}
    }

    if bestIndex == U32_MAX {
	return false, 0;
    } else {
	return true, bestIndex;
    }
}

get_any_queue_family_index :: (flag : VkQueueFlags, queueFamilies : [] VkQueueFamilyProperties) -> bool #must, u32 {
    for queueFamilies {
	if (flag & it.queueFlags) == flag {
	    return true, cast(u32) it_index;
	}
    }

    return false, 0;
}

get_queue_family_index :: (flag : VkQueueFlags, queueFamilies : [] VkQueueFamilyProperties, usedIndices : *[..] u32, deviceProps : VkPhysicalDeviceProperties) -> bool #must, u32 {
    found, index := get_dedicated_queue_family_index(flag, queueFamilies, usedIndices);
    if !found {
	log_vk(.INFO, tprint("Failed to find a dedicated Queue Family Index for flags: % on %, finding any available index with flag", flag, to_string(deviceProps.deviceName.data)));
	found, index = get_any_queue_family_index(flag, queueFamilies);
	if !found {
	    log_vk(.INFO, tprint("Failed to find any Queue Family Index for flags: % on %", flag, to_string(deviceProps.deviceName.data)));
	}
    }

    return found, index;
}

chain_physical_device_features :: (_1_1 : *VkPhysicalDeviceVulkan11Features, _1_2 : *VkPhysicalDeviceVulkan12Features, _1_3 : *VkPhysicalDeviceVulkan13Features) -> VkPhysicalDeviceFeatures2 {
    featureChain : VkPhysicalDeviceFeatures2;
    featureChain.pNext = _1_1;
    _1_1.pNext = _1_2;
    _1_2.pNext = _1_3;

    return featureChain;
}

queue_create_info :: (familyIndex : u32) -> VkDeviceQueueCreateInfo #must {
    defaultPriority : float32 = 0.0;
    
    queueInfo := VkDeviceQueueCreateInfo.{};
    queueInfo.queueFamilyIndex = familyIndex;
    queueInfo.queueCount = 1;
    queueInfo.pQueuePriorities = *defaultPriority;

    return queueInfo;
}

create_command_pool :: (device : VkDevice, queueFamilyIndex : u32, flags : VkCommandPoolCreateFlags = .RESET_COMMAND_BUFFER_BIT) -> VkCommandPool #must {
    info : VkCommandPoolCreateInfo;
    info.flags = flags;
    info.queueFamilyIndex = queueFamilyIndex;
    cmdPool : VkCommandPool;
    check_vk(vkCreateCommandPool(device, *info, null, *cmdPool), "Failed to create Command Pool");
    return cmdPool;
}

vk_debug_callback :: (messageSeverity : VkDebugUtilsMessageSeverityFlagBitsEXT, messageType : VkDebugUtilsMessageTypeFlagsEXT, pCallbackData : *VkDebugUtilsMessengerCallbackDataEXT, pUserData : *void) -> VkBool32 #c_call {
    logType := Log_Type.DEV;
    if messageSeverity & .WARNING_BIT_EXT then logType = .WARN;
    if messageSeverity & .ERROR_BIT_EXT then logType = .ERROR;

    push_context {
        print("VALIDATION: %\n", to_string(pCallbackData.pMessage));
        log_vk(logType, tprint("VALIDATION: %", to_string(pCallbackData.pMessage)));
    }

    return VK_FALSE;
}

check_vk :: (result : VkResult, errMsg : string, errType := Log_Type.FATAL) #expand {
    if result != .SUCCESS {
        log_vk(errType, tprint("%: %", errMsg, enum_value_to_name(result)));
    }
}

log_vk :: (type : Log_Type, s : string) {
    log(type, tprint("[VULKAN] %", s));
}
