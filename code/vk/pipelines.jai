/*
Project: Loam
File: vk/pipelines.jai
Author: Brock Salmon
Created: 19MAY2025
*/

GraphicsPipelineInfo :: struct {
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

build_graphics_pipeline :: (vk : *Vk, using pipelineInfo : *GraphicsPipelineInfo) -> VkPipeline #must {
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
    check_vk(vkCreateGraphicsPipelines(vk.device, null, 1, *graphicsPipelineCreateInfo, null, *pipeline), "Failed to create Graphics Pipeline");
    return pipeline;
}

set_pipeline_shaders :: (using pipelineInfo : *GraphicsPipelineInfo, vertexShader : VkShaderModule, fragmentShader : VkShaderModule) {
    array_reset(*shaderStages);
    array_add(*shaderStages, make_shader_stage_info(.VERTEX_BIT, vertexShader));
    array_add(*shaderStages, make_shader_stage_info(.FRAGMENT_BIT, fragmentShader));
}

set_pipeline_input_topology :: (using pipelineInfo : *GraphicsPipelineInfo, topology : VkPrimitiveTopology) {
    inputAssembly.topology = topology;
}

set_pipeline_polygon_mode :: (using pipelineInfo : *GraphicsPipelineInfo, mode : VkPolygonMode) {
    rasteriser.polygonMode = mode;
    rasteriser.lineWidth = 1;
}

set_pipeline_cull_mode :: (using pipelineInfo : *GraphicsPipelineInfo, cullFlags : VkCullModeFlags, frontFaceDirection : VkFrontFace) {
    rasteriser.cullMode = cullFlags;
    rasteriser.frontFace = frontFaceDirection;
}

MultisamplingMode :: enum u8 {
    None;
}

set_pipeline_multisampling_mode :: (using pipelineInfo : *GraphicsPipelineInfo, mode : MultisamplingMode) {
    if #complete mode == {
	case .None; {
	    multisampling.rasterizationSamples = ._1_BIT;
	    multisampling.minSampleShading = 1;
	}
    }
}

BlendingMode :: enum u8 {
    None;
    Text;
    Additive;
    Alpha;
}

set_pipeline_blending_mode :: (using pipelineInfo : *GraphicsPipelineInfo, enabled : bool, mode := BlendingMode.None) {
    blending = .{};
    blending.colorWriteMask = .R_BIT | .G_BIT | .B_BIT | .A_BIT;

    if enabled {
	if mode == .None {
	    log(.WARN, "Blending cannot be enabled for a pipeline without a Blending Mode being specified");
	    return;
	}

	blending.blendEnable = VK_TRUE;
	blending.dstColorBlendFactor = .DST_ALPHA;
	blending.colorBlendOp = .ADD;
	blending.srcAlphaBlendFactor = .ONE;
	blending.dstAlphaBlendFactor = .ZERO;
	blending.alphaBlendOp = .ADD;
	
	if #complete mode == {
	    case .None;
	    
	    case .Text; {
		blending.srcColorBlendFactor = .SRC_ALPHA;
		blending.srcAlphaBlendFactor = .SRC_ALPHA;
		blending.dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA;
		blending.dstAlphaBlendFactor = .ONE_MINUS_SRC_ALPHA;
	    }
	    
	    case .Additive; blending.srcColorBlendFactor = .ONE;
	    case .Alpha;    blending.srcColorBlendFactor = .ONE_MINUS_DST_ALPHA;
	}
    }
}

set_pipeline_colour_attachment_format :: (using pipelineInfo : *GraphicsPipelineInfo, format : VkFormat) {
    colourAttachFormat = format;
    renderInfo.colorAttachmentCount = 1;
    renderInfo.pColorAttachmentFormats = *colourAttachFormat;
}

set_pipeline_depth_format :: (using pipelineInfo : *GraphicsPipelineInfo, format : VkFormat) {
    renderInfo.depthAttachmentFormat = format;
}

set_pipeline_depth_test_enabled :: (using pipelineInfo : *GraphicsPipelineInfo, enabled : bool, writeEnabled : bool, compareOp : VkCompareOp) {
    depthStencil = .{};
    depthStencil.depthWriteEnable = ifx writeEnable then VK_TRUE;
    depthStencil.maxDepthBounds = 1;
    if enabled {
	depthStencil.depthTestEnable = VK_TRUE;
	depthStencil.depthCompareOp = compareOp;
    }
}

Pipeline_UI :: struct {
    layout             : VkPipelineLayout;
    pipeline           : VkPipeline;
    textPipeline       : VkPipeline;
    uiDescriptorLayout : VkDescriptorSetLayout;
}

