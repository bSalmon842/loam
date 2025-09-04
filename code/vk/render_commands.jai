/*
Project: Loam
File: vk/render_commands.jai
Author: Brock Salmon
Created: 23JUN2025
*/

MeshRenderCommand :: struct {
    buffers : *GPUBuffers;
    pushConstants : MeshPushConstants;
}

add_ui_render_command :: (elem : *UI_Element) {
    if #complete elem.type == {
	case .Empty; return;
	
	case .Text;   for elem.text.glyphs { add_sprite_render_command(.UI_Text, *it.renderable, it.transform, elem.interact.hovered, elem.interact.hoverTint); }
	case .Sprite; add_sprite_render_command(.UI_Sprite, elem.sprite.renderable, elem.sprite.transform, elem.interact.hovered, elem.interact.hoverTint);
    }
}

add_render_command :: (pipelineType : PipelineType, camera : *Camera, renderable : *Renderable, transform : Transform,
		       useTintOverride : bool = false, tintOverride : Vector4 = DEFAULT_TEXTURE_TINT) {
    assert(loam.renderActive, "Not within the render section, be sure to call loam_start_render before adding and loam_finish_render after processing draw calls");
    if !renderable.buffers.indexBuffer then return;
    
    pipeline := *vk.pipelines[pipelineType];
    
    render := New(MeshRenderCommand);
    found := false;
    for * pipeline.renderCommands {
	if !it.* {
	    it.* = render;
	    found = true;
	    break;
	}
    }
    if !found {
	log(.ERROR, "Render Command array is full");
	free(render);
	return;
    }
    
    // Save and reset the camera projection for after the command is made and use the pipeline's projection mode
    currentCameraProjection := camera.isOrthographic;
    camera.isOrthographic = pipeline.orthographic;
    
    render.buffers = renderable.buffers;
    render.pushConstants = .{ get_transform_matrix(transform, renderable.dimensions) * get_view_matrix(camera) * get_projection_matrix(camera),
			      ifx useTintOverride then tintOverride else renderable.tint, renderable.texture.index, render.buffers.vertex.bufferAddress };
    
    camera.isOrthographic = currentCameraProjection;
}

add_sprite_render_command :: (pipelineType : PipelineType, renderable : Renderable2D, transform : Transform,
			      useTintOverride : bool = false, tintOverride : Vector4 = DEFAULT_TEXTURE_TINT) {
    assert(loam.renderActive, "Not within the render section, be sure to call loam_start_render before adding and loam_finish_render after processing draw calls");
    
    pipeline := *vk.pipelines[pipelineType];
    if pipeline.sprites.count == MAX_SPRITES then return;

    spriteInfo := GPUSpriteInfo.{
	get_transform_matrix(transform, renderable.dimensions),
	ifx useTintOverride then tintOverride else renderable.tint,
	renderable.uv0, renderable.uv1,
	renderable.dimensions,
	renderable.texture.index, 0
    };

    pipeline.sprites.array[pipeline.sprites.count] = spriteInfo;
    pipeline.sprites.count += 1;
}

render_command :: (cmdBuffer : VkCommandBuffer, render : *MeshRenderCommand, pipelineLayout : VkPipelineLayout) {
    vkCmdPushConstants(cmdBuffer, pipelineLayout, .VERTEX_BIT, 0, size_of(MeshPushConstants), *render.pushConstants);
    
    vkCmdBindIndexBuffer(cmdBuffer, render.buffers.indexBuffer.buffer, 0, .UINT32);
    vkCmdDrawIndexed(cmdBuffer, render.buffers.indexCount, 1, 0, 0, 0);
}

render_sprite_batch :: (cmdBuffer : VkCommandBuffer, pushConstants : SpritePushConstants, spriteCount : u32, pipelineLayout : VkPipelineLayout) {
    vkCmdPushConstants(cmdBuffer, pipelineLayout, .VERTEX_BIT, 0, size_of(SpritePushConstants), *pushConstants);
    
    vkCmdBindIndexBuffer(cmdBuffer, vk.defaultPlaneIndexBuffer.buffer, 0, .UINT32);
    vkCmdDrawIndexed(cmdBuffer, DEFAULT_PLANE_INDICES.count, spriteCount, 0, 0, 0);
}
