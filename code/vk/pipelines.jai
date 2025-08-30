/*
Project: Loam
File: vk/pipelines.jai
Author: Brock Salmon
Created: 19MAY2025
*/

PipelineType :: enum {
    Mesh;
    Sprite;
    UI_Sprite;
    UI_Text;
}

GraphicsPipelineBuildInfo :: struct {
    shaderStages       : [..] VkPipelineShaderStageCreateInfo;
    inputAssembly      : VkPipelineInputAssemblyStateCreateInfo;
    rasteriser         : VkPipelineRasterizationStateCreateInfo;
    blending           : VkPipelineColorBlendAttachmentState;
    multisampling      : VkPipelineMultisampleStateCreateInfo;
    layout             : VkPipelineLayout;
    depthStencil       : VkPipelineDepthStencilStateCreateInfo;
    renderInfo         : VkPipelineRenderingCreateInfo;
    colourAttachFormat : VkFormat;
}

build_graphics_pipeline :: (using pipelineInfo : *GraphicsPipelineBuildInfo) -> VkPipeline {
    // NOTE: We use a dynamic viewport state, so say we have a single viewport and scissor as they will be bound during rendering
    viewportStateCreateInfo := VkPipelineViewportStateCreateInfo.{ viewportCount = 1, scissorCount = 1 };
    colourBlendStateCreateInfo := VkPipelineColorBlendStateCreateInfo.{ logicOp = .COPY, attachmentCount = 1, pAttachments = *blending };
    vertexInputStateCreateInfo := VkPipelineVertexInputStateCreateInfo.{};

    dynamicStates := VkDynamicState.[ .VIEWPORT, .SCISSOR ];
    dynamicInfo := VkPipelineDynamicStateCreateInfo.{ dynamicStateCount = cast(u32) dynamicStates.count, pDynamicStates = dynamicStates.data };
    
    graphicsPipelineCreateInfo := VkGraphicsPipelineCreateInfo.{ .GRAPHICS_PIPELINE_CREATE_INFO, *renderInfo, 0, cast(u32) shaderStages.count, shaderStages.data,
							         *vertexInputStateCreateInfo, *inputAssembly, null, *viewportStateCreateInfo, *rasteriser, *multisampling,
							         *depthStencil, *colourBlendStateCreateInfo, *dynamicInfo, layout, null, 0, null, 0 };

    pipeline : VkPipeline;
    check_vk(vkCreateGraphicsPipelines(vk.device, vk.pipelineCache, 1, *graphicsPipelineCreateInfo, null, *pipeline), "Failed to create Graphics Pipeline");
    return pipeline;
}

set_pipeline_shaders :: (using pipelineInfo : *GraphicsPipelineBuildInfo, vertexShader : VkShaderModule, fragmentShader : VkShaderModule) {
    array_reset(*shaderStages);
    array_add(*shaderStages, make_shader_stage_info(.VERTEX_BIT, vertexShader));
    array_add(*shaderStages, make_shader_stage_info(.FRAGMENT_BIT, fragmentShader));
}

set_pipeline_input_topology :: (using pipelineInfo : *GraphicsPipelineBuildInfo, topology : VkPrimitiveTopology) {
    inputAssembly.topology = topology;
}

set_pipeline_polygon_mode :: (using pipelineInfo : *GraphicsPipelineBuildInfo, mode : VkPolygonMode) {
    rasteriser.polygonMode = mode;
    rasteriser.lineWidth = 1;
}

set_pipeline_cull_mode :: (using pipelineInfo : *GraphicsPipelineBuildInfo, cullFlags : VkCullModeFlags, frontFaceDirection : VkFrontFace) {
    rasteriser.cullMode = cullFlags;
    rasteriser.frontFace = frontFaceDirection;
}

MultisamplingMode :: enum u8 {
    None;
}

set_pipeline_multisampling_mode :: (using pipelineInfo : *GraphicsPipelineBuildInfo, mode : MultisamplingMode) {
    if #complete mode == {
	case .None; {
	    multisampling.rasterizationSamples = ._1_BIT;
	    multisampling.minSampleShading = 1;
	}
    }
}

BlendingMode :: enum u8 {
    None;
    Additive;
    Alpha;
}

set_pipeline_blending_mode :: (using pipelineInfo : *GraphicsPipelineBuildInfo, enabled : bool, mode := BlendingMode.None) {
    blending = .{};
    blending.colorWriteMask = .R_BIT | .G_BIT | .B_BIT | .A_BIT;

    if enabled {
	if mode == .None {
	    log(.WARN, "Blending cannot be enabled for a pipeline without a Blending Mode being specified");
	    return;
	}

	blending.blendEnable = VK_TRUE;
	
	if #complete mode == {
	    case .None;
	    
	    case .Additive; {
		blending.srcColorBlendFactor = .SRC_ALPHA;
		blending.dstColorBlendFactor = .ONE;
		blending.colorBlendOp = .ADD;

		blending.srcAlphaBlendFactor = .ONE;
		blending.dstAlphaBlendFactor = .ZERO;
		blending.alphaBlendOp = .ADD;
	    }
	    case .Alpha; {
		blending.srcColorBlendFactor = .SRC_ALPHA;
		blending.dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA;
		blending.colorBlendOp = .ADD;

		blending.srcAlphaBlendFactor = .ONE;
		blending.dstAlphaBlendFactor = .ZERO;
		blending.alphaBlendOp = .ADD;
	    }
	}
    }
}

set_pipeline_colour_attachment_format :: (using pipelineInfo : *GraphicsPipelineBuildInfo, format : VkFormat) {
    colourAttachFormat = format;
    renderInfo.colorAttachmentCount = 1;
    renderInfo.pColorAttachmentFormats = *colourAttachFormat;
}

set_pipeline_depth_format :: (using pipelineInfo : *GraphicsPipelineBuildInfo, format : VkFormat) {
    renderInfo.depthAttachmentFormat = format;
}

set_pipeline_depth_test_enabled :: (using pipelineInfo : *GraphicsPipelineBuildInfo, enabled : bool, writeEnabled : bool, compareOp : VkCompareOp) {
    depthStencil = .{};
    depthStencil.depthWriteEnable = ifx writeEnable then VK_TRUE;
    depthStencil.maxDepthBounds = 1;
    if enabled {
	depthStencil.depthTestEnable = VK_TRUE;
	depthStencil.depthCompareOp = compareOp;
    }
}

set_pipeline_layout :: (builder : *GraphicsPipelineBuildInfo, bufferSize : u32, pipelineType : PipelineType) {
    bufferRange := VkPushConstantRange.{ .VERTEX_BIT, 0, bufferSize };
    layout := VkPipelineLayoutCreateInfo.{ .PIPELINE_LAYOUT_CREATE_INFO, null, 0, 1, *vk.bindlessDescriptorLayout, 1, *bufferRange };
    check_vk(vkCreatePipelineLayout(vk.device, *layout, null, *builder.layout), tprint("Failed to create pipeline layout for %", pipelineType));
}

MAX_RENDER_COMMANDS :: 1024;
RenderingPipelineInfo :: struct {
    layout           : VkPipelineLayout;
    pipeline         : VkPipeline;
    orthographic     : bool;

    renderCommands : [MAX_RENDER_COMMANDS] *MeshRenderCommand;
}

draw_pipeline :: (cmdBuffer : VkCommandBuffer, pipeline : *RenderingPipelineInfo, drawExtent : VkExtent2D) {
    if pipeline.renderCommands.count == 0 then return;
    
    vkCmdBindPipeline(cmdBuffer, .GRAPHICS, pipeline.pipeline);
    
    colourAttachment := make_rendering_attachment_info(vk.drawImage.view, layout=.GENERAL);
    renderInfo := make_rendering_info(drawExtent, *colourAttachment, null);
    vkCmdBeginRendering(cmdBuffer, *renderInfo);

    viewport := VkViewport.{ width = cast(float) drawExtent.width, height = cast(float) drawExtent.height, minDepth = 0, maxDepth = 1 };
    vkCmdSetViewport(cmdBuffer, 0, 1, *viewport);
    
    scissor := VkRect2D.{ .{}, drawExtent };
    vkCmdSetScissor(cmdBuffer, 0, 1, *scissor);

    vkCmdBindDescriptorSets(cmdBuffer, .GRAPHICS, pipeline.layout, 0, 1, *vk.bindlessDescriptorSet, 0, null);
    for pipeline.renderCommands {
	if it {
	    render_command(cmdBuffer, it, pipeline.layout);
	}
    }
    
    vkCmdEndRendering(cmdBuffer);
}

init_pipelines :: () {
    // TODO: Investigate if saving/loading our cache to/from disk is worth it for our purposes
    cacheCreateInfo := VkPipelineCacheCreateInfo.{};
    check_vk(vkCreatePipelineCache(vk.device, *cacheCreateInfo, null, *vk.pipelineCache), "Failed to create pipeline cache");
    
    for enum_values_as_enum(PipelineType) {
	pipeline := *vk.pipelines[it];
	
	builder : GraphicsPipelineBuildInfo;
	vertShader : VkShaderModule;
	fragShader : VkShaderModule;
	
	if #complete it == {
	    case .Mesh; {
		pipeline.orthographic = false;
		
		vertShader = load_shader_module(vk.device, MESH_VERTEX_SHADER);
		fragShader = load_shader_module(vk.device, MESH_FRAGMENT_SHADER);

		set_pipeline_shaders(*builder, vertShader, fragShader);
		set_pipeline_input_topology(*builder, .TRIANGLE_LIST);
		set_pipeline_polygon_mode(*builder, .FILL);
		set_pipeline_cull_mode(*builder, .BACK_BIT, .COUNTER_CLOCKWISE);
		set_pipeline_multisampling_mode(*builder, .None);
		set_pipeline_blending_mode(*builder, false);
		set_pipeline_colour_attachment_format(*builder, vk.drawImage.format);
		set_pipeline_depth_format(*builder, .UNDEFINED);
		set_pipeline_layout(*builder, size_of(MeshPushConstants), it);
	    }
	    
	    case .Sprite; {
		pipeline.orthographic = true;
		
		vertShader = load_shader_module(vk.device, MESH_VERTEX_SHADER);
		fragShader = load_shader_module(vk.device, SPRITE_FRAGMENT_SHADER);

		set_pipeline_shaders(*builder, vertShader, fragShader);
		set_pipeline_input_topology(*builder, .TRIANGLE_LIST);
		set_pipeline_polygon_mode(*builder, .FILL);
		set_pipeline_cull_mode(*builder, .BACK_BIT, .COUNTER_CLOCKWISE);
		set_pipeline_multisampling_mode(*builder, .None);
		set_pipeline_blending_mode(*builder, true, .Alpha);
		set_pipeline_colour_attachment_format(*builder, vk.drawImage.format);
		set_pipeline_depth_format(*builder, .UNDEFINED);
		set_pipeline_layout(*builder, size_of(MeshPushConstants), it);
	    }
	    
	    case .UI_Sprite; {
		pipeline.orthographic = true;
		
		vertShader = load_shader_module(vk.device, UI_VERTEX_SHADER);
		fragShader = load_shader_module(vk.device, UI_FRAGMENT_SHADER);

		set_pipeline_shaders(*builder, vertShader, fragShader);
		set_pipeline_input_topology(*builder, .TRIANGLE_LIST);
		set_pipeline_polygon_mode(*builder, .FILL);
		set_pipeline_cull_mode(*builder, .BACK_BIT, .COUNTER_CLOCKWISE);
		set_pipeline_multisampling_mode(*builder, .None);
		set_pipeline_blending_mode(*builder, true, .Alpha);
		set_pipeline_colour_attachment_format(*builder, vk.drawImage.format);
		set_pipeline_depth_format(*builder, .UNDEFINED);
		set_pipeline_layout(*builder, size_of(MeshPushConstants), it);
	    }
	    
	    case .UI_Text; {
		pipeline.orthographic = true;
		
		vertShader = load_shader_module(vk.device, UI_VERTEX_SHADER);
		fragShader = load_shader_module(vk.device, TEXT_FRAGMENT_SHADER);
		
		set_pipeline_shaders(*builder, vertShader, fragShader);
		set_pipeline_input_topology(*builder, .TRIANGLE_LIST);
		set_pipeline_polygon_mode(*builder, .FILL);
		set_pipeline_cull_mode(*builder, .BACK_BIT, .COUNTER_CLOCKWISE);
		set_pipeline_multisampling_mode(*builder, .None);
		set_pipeline_blending_mode(*builder, false);
		set_pipeline_colour_attachment_format(*builder, vk.drawImage.format);
		set_pipeline_depth_format(*builder, .UNDEFINED);
		set_pipeline_layout(*builder, size_of(MeshPushConstants), it);
	    }
	}

	pipeline.layout = builder.layout;
	pipeline.pipeline = build_graphics_pipeline(*builder);

	vkDestroyShaderModule(vk.device, vertShader, null);
	vkDestroyShaderModule(vk.device, fragShader, null);
    }
}


