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

    ImGui.SetNextWindowPos(.{ 0, 0 });
    ImGui.SetNextWindowSize(.{ 350, 500 });
}

draw_imgui :: (cmdBuffer : VkCommandBuffer, imageView : VkImageView) {
    colourAttachment := VkRenderingAttachmentInfo.{ .RENDERING_ATTACHMENT_INFO, null, imageView, .GENERAL, 0, null, 0, .LOAD, .STORE, .{} };
    renderInfo := VkRenderingInfo.{ .RENDERING_INFO, null, 0, .{ .{ 0, 0 }, vk.swapchainExtent }, 1, 0, 1, *colourAttachment, null, null };

    vkCmdBeginRendering(cmdBuffer, *renderInfo);
    ImGui.ImplVulkan_RenderDrawData(ImGui.GetDrawData(), cmdBuffer);
    vkCmdEndRendering(cmdBuffer);
}

tooltipSet : VkDescriptorSet;

// TODO: Extend this for games
frame_imgui :: (metrics : *DebugMetrics) {
    ImGui.ImplVulkan_NewFrame();
    ImGui.ImplWin32_NewFrame();
    ImGui.NewFrame();
    
    ImGui.Begin("Dev Window");
    if ImGui.CollapsingHeader("Metrics") {
	ImGui.Text("General:");
	colour := ImGui.ImVec4.{ 1, 1, 1, 1 };
	if metrics.framesPerSecond < loam.refreshRate {
	    colour = .{ 1, 1, 0, 1 };
	} else if metrics.framesPerSecond < 30 {
	    colour = .{ 1, 0, 0, 1 };
	}
	
	ImGui.TextColored(colour, tprint("\tFrame Time: % / % (%Hz)", metrics.framesPerSecond, metrics.msPerFrame, loam.refreshRate));
	ImGui.Text(tprint("\tRAM Usage:  %", to_size_string(metrics.ramUsage)));
	
	ImGui.NewLine();
	
	ImGui.Text("Pipelines:");
	for metrics.pipelineDrawCalls {
	    if ImGui.CollapsingHeader(tprint("%\0", enum_value_to_name(cast(PipelineType) it_index)).data) {
		ImGui.Text(tprint("\tDraw Calls: % %", it, ifx vk.pipelines[it_index].isSpritePipeline then tprint("Rendered as Sprite Batch") else ""));
	    }
	}

	ImGui.NewLine();
    }

    if ImGui.CollapsingHeader("Config") {
	ImGui.Checkbox("vsync", *loam.config.vsync);

	devices := Audio.get_devices();
	if ImGui.BeginCombo("##audiodevices", loam.audioDevice.name.data) {
	    for devices {
		selected := loam.audioDevice.device_index == it.device_index;
		if ImGui.Selectable(it.name.data, selected) then change_audio_device(it);
		if selected then ImGui.SetItemDefaultFocus();
	    }
	    
	    ImGui.EndCombo();
	}
	
	if ImGui.Button("Save Config File") {
	    save_config();
	}
	
	ImGui.NewLine();
    }
    
    if ImGui.CollapsingHeader("Resource Counts") {
	if ImGui.CollapsingHeader(tprint("Images: %\0", loam.assets.images.count).data) {
	    for loam.assets.images.array {
		if it {
		    colour := ImGui.ImVec4.{ 1, 1, 1, 1 };
		    if it.core {
			colour = .{ 0.71, 0.45, 1, 1 };
		    }
		    
		    ImGui.TextColored(colour, tprint("\t%", it.name));
		    if ImGui.IsItemHovered() {
			drawList := ImGui.GetWindowDrawList();
			min := ImGui.GetItemRectMin();
			max := ImGui.GetItemRectMax();
			max.x = min.x + ImGui.GetWindowContentRegionMax().x;
			ImGui.ImDrawList.AddRectFilled(drawList, min, max, 0x40808080);
			
			if ImGui.BeginTooltip() {
			    if tooltipSet {
				ImGui.ImplVulkan_RemoveTexture(tooltipSet);
			    }

			    scaledImageWidth := cast(float) it.image.extent.width;
			    scaledImageHeight := cast(float) it.image.extent.height;
			    imageMaxDim := 500.0;
			    if scaledImageWidth > imageMaxDim || scaledImageHeight > imageMaxDim {
				fitScaleX := imageMaxDim / it.image.extent.width;
				fitScaleY := imageMaxDim / it.image.extent.height;
				if fitScaleX < fitScaleY {
				    scaledImageWidth *= fitScaleX;
				    scaledImageHeight *= fitScaleX;
				} else {
				    scaledImageWidth *= fitScaleY;
				    scaledImageHeight *= fitScaleY;
				}
			    }
			    
			    tooltipSet = ImGui.ImplVulkan_AddTexture(vk.defaultSampler_Nearest, it.image.view, .SHADER_READ_ONLY_OPTIMAL);
			    ImGui.Image(tooltipSet, ImGui.ImVec2.{ scaledImageWidth, scaledImageHeight });
			    ImGui.EndTooltip();
			}
		    }
		}
	    }
	}

	if ImGui.CollapsingHeader(tprint("Audio: %\0", loam.assets.audios.count).data) {
	    for loam.assets.audios.array {
		if it {
		    colour := ImGui.ImVec4.{ 1, 1, 1, 1 };
		    if it.core {
			colour = .{ 0.71, 0.45, 1, 1 };
		    }
		    
		    ImGui.TextColored(colour, tprint("\t%", it.name));
		}
	    }
	}
	
	ImGui.NewLine();
    }

    if ImGui.CollapsingHeader("Playing Audio") {
	ImGui.Text("Playing Audio:");
	ImGui.BeginTable("##audiotable", 3, .Borders);
	ImGui.TableSetupColumn("Name");
	ImGui.TableSetupColumn("Time");
	ImGui.TableSetupColumn("Loop", .WidthFixed, 50.0);
	ImGui.TableHeadersRow();
	
	for loam.activeAudio {
	    ImGui.TableNextRow();

	    ImGui.TableSetColumnIndex(0);
	    ImGui.Text(it.sound_data.resource.name);
	    
	    ImGui.TableSetColumnIndex(1);
	    progress := it.play_cursor / cast(float64) it.sound_data.sampling_rate;
	    duration := cast(float64) (it.sound_data.buffer.count / size_of(u16)) / cast(float64) it.sound_data.sampling_rate / cast(float64) it.sound_data.nchannels;
	    ImGui.Text(tprint("% / %", convert_duration_to_minutes(progress), convert_duration_to_minutes(duration)));
	    
	    ImGui.TableSetColumnIndex(2);
	    ImGui.Text(tprint("%", cast(bool) (it.user_flags & .REPEATING)));
	}
	
	ImGui.EndTable();
	
	ImGui.NewLine();
	ImGui.Text("Volumes");
	ImGui.Text("\tMaster");
	if ImGui.SliderFloat("##mastervolume", *loam.config.masterVolume, 0.0, 1.0, "%.2f") then Audio.set_master_volume(loam.config.masterVolume);
	ImGui.Text("\tBackground");
	ImGui.SliderFloat("##bgvolume", *loam.config.bgVolume, 0.0, 1.0, "%.2f");
	ImGui.Text("\tSFX");
	ImGui.SliderFloat("##sfxvolume", *loam.config.sfxVolume, 0.0, 1.0, "%.2f");
	
	ImGui.NewLine();
    }

    if ImGui.CollapsingHeader("Game State") {
	ImGui.Text(tprint("Gameplay State: %", loam.gameplayState));
	
	ImGui.NewLine();
    }
    ImGui.End();
    
    ImGui.Render();
}

