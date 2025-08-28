/*
Project: Loam
File: imgui.jai
Author: Brock Salmon
Created: 28AUG2025
*/

init_imgui :: (window : Window_Type) {
    // Create Desc Pool
    poolSizes := VkDescriptorPoolSize.[
        .{ .SAMPLER,                1000 },
        .{ .COMBINED_IMAGE_SAMPLER, 1000 },
        .{ .SAMPLED_IMAGE,          1000 },
        .{ .STORAGE_IMAGE,          1000 },
        .{ .UNIFORM_TEXEL_BUFFER,   1000 },
        .{ .STORAGE_TEXEL_BUFFER,   1000 },
        .{ .UNIFORM_BUFFER,         1000 },
        .{ .STORAGE_BUFFER,         1000 },
        .{ .UNIFORM_BUFFER_DYNAMIC, 1000 },
        .{ .STORAGE_BUFFER_DYNAMIC, 1000 },
        .{ .INPUT_ATTACHMENT,       1000 }
    ];
    
    poolCreateInfo := VkDescriptorPoolCreateInfo.{ .DESCRIPTOR_POOL_CREATE_INFO, null, .FREE_DESCRIPTOR_SET_BIT, 1000, cast(u32) poolSizes.count, poolSizes.data };
    imguiPool : VkDescriptorPool;
    check_vk(vkCreateDescriptorPool(vk.device, *poolCreateInfo, null, *imguiPool), "Failed to create ImGui Descriptor Pool");
    
    // Init ImGui library
    ImGui.CreateContext();
    #if OS == .WINDOWS { ImGui.ImplWin32_Init(window); }
    
    imguiFormat := vk.swapchainFormat;
    imguiPipeline := VkPipelineRenderingCreateInfo.{ .PIPELINE_RENDERING_CREATE_INFO, null, 0, 1, *imguiFormat, 0, 0 };
    imguiVulkanInitInfo := ImGui.ImplVulkan_InitInfo.{ vk.instance, vk.physicalDevice, vk.device, 0, vk.graphicsQueue, imguiPool, null, 3, 3, ._1_BIT, null, 0, true, imguiPipeline, null, null, 0 };
    ImGui.ImplVulkan_Init(*imguiVulkanInitInfo);
    
    create_imgui_vulkan_fonts :: (cmdBuffer : VkCommandBuffer, data : *void) { ImGui.ImplVulkan_CreateFontsTexture(); }
    add_update_command(create_imgui_vulkan_fonts, null, null);
    
}

draw_imgui :: (cmdBuffer : VkCommandBuffer, imageView : VkImageView) {
    colourAttachment := VkRenderingAttachmentInfo.{ .RENDERING_ATTACHMENT_INFO, null, imageView, .GENERAL, 0, null, 0, .LOAD, .STORE, .{} };
    renderInfo := VkRenderingInfo.{ .RENDERING_INFO, null, 0, .{ .{ 0, 0 }, vk.swapchainExtent }, 1, 0, 1, *colourAttachment, null, null };

    vkCmdBeginRendering(cmdBuffer, *renderInfo);
    ImGui.ImplVulkan_RenderDrawData(ImGui.GetDrawData(), cmdBuffer);
    vkCmdEndRendering(cmdBuffer);
}

frame_imgui :: (metrics : *DebugMetrics) {
    ImGui.ImplVulkan_NewFrame();
    ImGui.ImplWin32_NewFrame();
    ImGui.NewFrame();
    
    ImGui.SetNextWindowPos(.{ 0, 0 });
    ImGui.SetNextWindowSize(.{ 300, 600 });
    ImGui.Begin("Dev Window");
    if ImGui.CollapsingHeader("Metrics") {
	ImGui.Text(tprint("\tFrame Time: % / % (%Hz)", metrics.framesPerSecond, metrics.msPerFrame, refreshRate));
	ImGui.Text(tprint("\t RAM Usage: %", to_size_string(metrics.ramUsage)));
	ImGui.Text(tprint("\tDraw Calls: % (D: %)", metrics.nonDebugDrawCalls, metrics.totalDrawCalls - metrics.nonDebugDrawCalls));
    }
    if ImGui.CollapsingHeader("Resource Counts") {
	ImGui.Text(tprint("\tImage: %", loam.assets.images.count));
    }
    ImGui.End();
    
    ImGui.Render();
}

