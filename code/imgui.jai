/*
Project: Loam
File: imgui.jai
Author: Brock Salmon
Created: 28AUG2025
*/

check_vk_imgui :: (result : VkResult) #c_call {
    push_context {
	if result != .SUCCESS {
            log_vk(.WARN, "VK CHECK FROM IMGUI: %", enum_value_to_name(result));
	}
    }
}

init_imgui :: () {
    // Init ImGui library
    ImGui.CreateContext();
    ImGui.ImplSDL3_InitForVulkan(loam.window);
    
    imguiFormat := vk.swapchainFormat;
    imguiPipelineRendering := VkPipelineRenderingCreateInfo.{ .PIPELINE_RENDERING_CREATE_INFO, null, 0, 1, *imguiFormat, 0, 0 };
    imguiPipeline := ImGui.ImplVulkan_PipelineInfo.{ null, 0, ._1_BIT, imguiPipelineRendering };

    vertShaderCreateInfo := VkShaderModuleCreateInfo.{ codeSize = cast(u64) IMGUI_VERT.code.count, pCode = cast(*u32) IMGUI_VERT.code.data };
    fragShaderCreateInfo := VkShaderModuleCreateInfo.{ codeSize = cast(u64) IMGUI_FRAG.code.count, pCode = cast(*u32) IMGUI_FRAG.code.data };
    imguiVulkanInitInfo := ImGui.ImplVulkan_InitInfo.{ VK_API_VERSION_1_3, vk.instance, vk.physicalDevice, vk.device, 0, vk.graphicsQueue, null, 1024, 3, 3, null,
						       imguiPipeline, true, null, check_vk_imgui, 1024*1024, vertShaderCreateInfo, fragShaderCreateInfo };
    ImGui.ImplVulkan_Init(*imguiVulkanInitInfo);

    ImGui.StyleColorsClassic();
    
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
    ImGui.ImplSDL3_NewFrame();
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
	    if ImGui.CollapsingHeader(tprint("\t%\0", enum_value_to_name(cast(PipelineType) it_index)).data) {
		ImGui.Text(tprint("\tDraw Calls: % %", it, ifx vk.pipelines[it_index].isSpritePipeline then tprint("Rendered as Sprite Batch") else ""));
	    }
	}
    }

    ImGui.PushStyleColor(.Header, ImGui.ImVec4.{ 0.2, 0.2, 0.2, 1.0 });
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
    }
    ImGui.PopStyleColor();

    ImGui.PushStyleColor(.Header, ImGui.ImVec4.{ 0.8, 0.1, 0.1, 1.0 });
    if ImGui.CollapsingHeader("Assets") {
	if ImGui.CollapsingHeader("\tResource Counts") {
	    if ImGui.CollapsingHeader(tprint("\t\tImages: %\0", loam.assets.images.count).data) {
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
				tooltipRef := ImGui.ImTextureRef.{ null, cast(ImGui.ImTextureID) tooltipSet };
				ImGui.Image(tooltipRef, ImGui.ImVec2.{ scaledImageWidth, scaledImageHeight });
				ImGui.EndTooltip();
			    }
			}
		    }
		}
	    }

	    if ImGui.CollapsingHeader(tprint("\t\tAudio: %\0", loam.assets.audios.count).data) {
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

	    if ImGui.CollapsingHeader(tprint("\t\tJSON: %\0", loam.assets.json.count).data) {
		for loam.assets.json.array {
		    if it {
			render_json_object(it.json, 0);
		    }
		}
	    }
	    
	    if ImGui.CollapsingHeader(tprint("\t\tGLTF: %\0", loam.assets.gltf.count).data) {
		for loam.assets.gltf.array {
		    if it {
			colour := ImGui.ImVec4.{ 1, 1, 1, 1 };
			if it.core {
			    colour = .{ 0.71, 0.45, 1, 1 };
			}
			
			ImGui.TextColored(colour, tprint("\t%", it.name));
		    }
		}
	    }
	}

	if ImGui.CollapsingHeader("\tPlaying Audio") {
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
	}
    }
    ImGui.PopStyleColor();

    ImGui.PushStyleColor(.Header, ImGui.ImVec4.{ 0.1, 0.1, 0.8, 1.0 });
    if ImGui.CollapsingHeader("Input") {
	ImGui.Text("Active Input: %", loam.input.activeType);
	ImGui.Text("KBM Timestamp:     %", loam.input.keyboardMouseTimestamp);
	ImGui.Text("Gamepad Timestamp: %", loam.input.gamepadTimestamp);
	ImGui.Text("Touch Timestamp:   %", loam.input.touchscreenTimestamp);
	ImGui.NewLine();
	if ImGui.CollapsingHeader("\tDevices") {
	    if SDL.has_keyboard() {
		if ImGui.CollapsingHeader("\t\tKeyboard") {
		    keyCount : s32;
		    keys := SDL.get_keyboard_state(*keyCount);
		    ImGui.Text("Active Key Scancodes:");
		    for enum_values_as_enum(SDL.Scancode) {
			if keys[it] then ImGui.BulletText("%", it);
		    }

		    ImGui.NewLine();
		    modState := SDL.get_mod_state();
		    ImGui.Text("Active Key Mods:");
		    for enum_values_as_enum(SDL.Keymod) {
			if modState & it != 0 then ImGui.BulletText("%", it);
		    }
		}
	    }

	    if SDL.has_mouse() {
		if ImGui.CollapsingHeader("\t\tMouse") {
		    relX, relY : float32;
		    mouseButtons := SDL.get_relative_mouse_state(*relX, *relY);
		    ImGui.Text("Rel X: % | Rel Y: %", relX, relY);

		    x, y : float32;
		    SDL.get_mouse_state(*x, *y);
		    ImGui.Text("X: % | Y: %", x, y);

		    for 1 .. 5 {
			mouseValue := SDL.BUTTON_MASK(cast(s32) it) & cast(s32) mouseButtons;
			if mouseValue != 0 {
			    ImGui.BulletText("%", cast(SDL.Mouse_Button_Flags) mouseValue);
			}
		    }
		}
	    }

	    if loam.input.gamepad {
		if ImGui.CollapsingHeader(tprint("\t\tGamepad (%)\0", to_string(SDL.get_gamepad_name_for_id(SDL.get_gamepad_id(loam.input.gamepad)))).data) {
		    ImGui.Text("Buttons:");
		    for enum_values_as_enum(SDL.Gamepad_Button) {
			if it != .INVALID && it != .COUNT {
			    if SDL.get_gamepad_button(loam.input.gamepad, it) {
				ImGui.BulletText("%", to_string(SDL.get_gamepad_string_for_button(it)));
			    }
			}
		    }
		    
		    ImGui.NewLine();

		    ImGui.Text("Axes");
		    for enum_values_as_enum(SDL.Gamepad_Axis) {
			if it != .INVALID && it != .COUNT && SDL.gamepad_has_axis(loam.input.gamepad, it) {
			    axisValue := SDL.get_gamepad_axis(loam.input.gamepad, it);
			    if axisValue == S16_MIN then axisValue += 1;
			    if it == .LEFTY || it == .RIGHTY then axisValue = -axisValue; // NOTE: SDL stick Y direction is reversed to what we expect
			    normalAxis := normalise_neg_1_to_1(cast(float32) axisValue, cast(float32) S16_MIN + 1.0, cast(float32) S16_MAX);
			    ImGui.BulletText("%: % (%)", it, axisValue, normalAxis);
			}
		    }
		}
	    }

	    // TODO: Touch inputs
	}

	if ImGui.CollapsingHeader("\tBindings") {
	    ImGui.NewLine();
	    for loam.keybinds {
		name, binding := it_index, it;
		ImGui.Text(name);
		
		ImGui.Text("buttons_as_axis: %", binding.buttonsAsAxis);
		ImGui.Text("invert_axis: %", binding.invertAxis);
		ImGui.Text("inner_deadzone: %", binding.innerDeadzone);
		ImGui.Text("outer_deadzone: %", binding.outerDeadzone);

		// TODO: Add visuals for showing which button is pressed
		
		ImGui.Text("keyboard: [ ");
		for binding.keyboard {
		    ImGui.SameLine();
		    if it_index == binding.keyboard.count-1 {
			ImGui.Text("%", it);
		    } else {
			ImGui.Text("%, ", it);
		    }
		}
		ImGui.SameLine();
		ImGui.Text(" ]");
		
		ImGui.Text("keyboard_mod: [ ");
		for binding.keyboardMod {
		    ImGui.SameLine();
		    if it_index == binding.keyboardMod.count-1 {
			ImGui.Text("%", it);
		    } else {
			ImGui.Text("%, ", it);
		    }
		}
		ImGui.SameLine();
		ImGui.Text(" ]");

		ImGui.Text("mouse_button: [ ");
		for binding.mouseButton {
		    ImGui.SameLine();
		    mouseValue := cast(SDL.Mouse_Button_Flags) SDL.BUTTON_MASK(cast(s32) it);
		    if it_index == binding.mouseButton.count-1 {
			ImGui.Text("%", mouseValue);
		    } else {
			ImGui.Text("%, ", mouseValue);
		    }
		}
		ImGui.SameLine();
		ImGui.Text(" ]");
		
		ImGui.Text("mouse_axis: [ ");
		for binding.mouseAxis {
		    ImGui.SameLine();
		    if it_index == binding.mouseAxis.count-1 {
			ImGui.Text("%", it);
		    } else {
			ImGui.Text("%, ", it);
		    }
		}
		ImGui.SameLine();
		ImGui.Text(" ]");

		ImGui.Text("gamepad_button: [ ");
		for binding.gamepadButton {
		    ImGui.SameLine();
		    if it_index == binding.gamepadButton.count-1 {
			ImGui.Text("%", it);
		    } else {
			ImGui.Text("%, ", it);
		    }
		}
		ImGui.SameLine();
		ImGui.Text(" ]");
		
		ImGui.Text("gamepad_axis: [ ");
		for binding.gamepadAxis {
		    ImGui.SameLine();
		    if it_index == binding.gamepadAxis.count-1 {
			ImGui.Text("%", it);
		    } else {
			ImGui.Text("%, ", it);
		    }
		}
		ImGui.SameLine();
		ImGui.Text(" ]");
		
		ImGui.NewLine();
	    }
	}
    }
    ImGui.PopStyleColor();

    ImGui.PushStyleColor(.Header, ImGui.ImVec4.{ 0.3, 0.3, 0.0, 1.0 });
    if ImGui.CollapsingHeader("Collision") {
	ImGui.Checkbox("Show Colliders", *__showColliders);
    }
    ImGui.PopStyleColor();
    
    ImGui.PushStyleColor(.Header, ImGui.ImVec4.{ 0.3, 0.3, 0.3, 1.0 });
    if ImGui.CollapsingHeader("Entities") {
	for < enum_values_as_enum(EntityUpdateRate) {
	    if ImGui.CollapsingHeader(tprint("%\0", it).data) {
		ImGui.PushStyleColor(.Header, ImGui.ImVec4.{ 0.15, 0.15, 0.15, 1.0 });
		for loam.entities[it] {
		    if ImGui.CollapsingHeader(tprint("\t%\0", it.name).data) {
			render_transform(*it.transform, it.name);
			if it.useModel {
			    ImGui.NewLine();
			    ImGui.Text("Nodes:");
			    render_model_nodes(it.model.nodes, it.model, 0);
			    ImGui.NewLine();
			}
		    }
		}
		ImGui.PopStyleColor();
	    }
	}
    }
    ImGui.PopStyleColor();
    
    ImGui.PushStyleColor(.Header, ImGui.ImVec4.{ 0.05, 0.4, 0.05, 1.0 });
    if ImGui.CollapsingHeader("Game State") {
	ImGui.Text(tprint("Gameplay State: %", loam.gameplayState));
    }
    ImGui.PopStyleColor();
    ImGui.End();
    
    ImGui.Render();
}

render_model_nodes :: (nodes : ModelNodeList, model : *Model, depth : u32) {
    tabString := get_tab_level_string(depth);
    
    for nodes {
	nodeName := it_index;
	if ImGui.CollapsingHeader(tprint("%1%2\0", tabString, nodeName).data) {
	    ImGui.Checkbox(tprint("Active##%\0", nodeName).data, *it.active);
	    if it.node.meshIndex > -1 {
		ImGui.Text("Mesh:");
		mesh := model.resource.gltf.meshes[it.node.meshIndex];
		ImGui.Text(tprint("\tName:", mesh.name));
		for mesh.prims {
		    ImGui.Text(tprint("\tPrim %", it_index));
		    ImGui.SameLine();
		    ImGui.Checkbox(tprint("\tActive##%_%\0", nodeName, it_index).data, *it.active);
		}
	    }
	    ImGui.Text("Nodes:");
	    render_model_nodes(it.children, model, depth + 1);
	}
    }
}

render_transform :: (transform : *Transform, name : string) {
    ImGui.DragFloat3(tprint("Position##position_%\0", name).data, *transform.position.component, 0.001);
    euler := quaternion_to_euler(transform.orientation);
    if ImGui.DragFloat3(tprint("Orientation##orientation_%\0", name).data, *euler.component, 0.001) {
	transform.orientation = euler_to_quaternion(euler);
    }
    ImGui.DragFloat3(tprint("Scale##scale_%\0", name).data, *transform.scale.component, 0.001);
}

render_json_object :: (value : *JSON_Value, tabLevel : u32) {
    tabString := get_tab_level_string(tabLevel);
    internalTabString := get_tab_level_string(tabLevel + 1);
    
    if #complete value.type == {
	case .Invalid;
	
	case .Array; #through;
	case .Object; {
	    if ImGui.CollapsingHeader(tprint("%1%2\0", tabString, value.name).data) {
		for value.values {
		    render_json_object(it, tabLevel + 1);
		}
	    }
	}

	case .Number; {
	    ImGui.Text(tprint("%\"%\" : %", internalTabString, value.name, value.value_float));
	}

	case .String; {
	    ImGui.Text(tprint("%\"%\" : %", internalTabString, value.name, value.value_string));
	}

	case .Boolean; {
	    ImGui.Text(tprint("%\"%\" : %", internalTabString, value.name, value.value_bool));
	}

	case .Null; {
	    ImGui.Text(tprint("%\"%\" : null", internalTabString, value.name));
	}
    }
}

get_tab_level_string :: (tabLevel : u32) -> string {
    if tabLevel == 0 then return "";
    builder : String_Builder;
    builder.allocator = temp;
    for 0 .. tabLevel-1 {
	print_to_builder(*builder, "\t");
    }

    return builder_to_string(*builder);
}

