/*
Project: Loam
File: vk/render_commands.jai
Author: Brock Salmon
Created: 23JUN2025
*/

RenderCommand :: struct {
    buffers : *MeshBuffers;
    pushConstants : AllPushConstants;
}

add_ui_render_command :: (elem : *UI_Element) {
    if #complete elem.type == {
	case .Empty; return;
	
	case .Text;   for elem.text.glyphs { add_render_command(.UI_Text, loam.uiCamera, *it.renderable, it.transform, elem.interact.hovered, elem.interact.hoverTint); }
	case .Sprite; add_render_command(.UI_Sprite, loam.uiCamera, *elem.sprite.renderable, elem.sprite.transform, elem.interact.hovered, elem.interact.hoverTint);
    }
}

add_render_command :: (pipelineType : PipelineType, camera : *Camera, renderable : *Renderable, transform : Transform,
		       useTintOverride : bool = false, tintOverride : Vector4 = DEFAULT_TEXTURE_TINT) {
    assert(loam.renderActive, "Not within the render section, be sure to call loam_start_render before adding and loam_finish_render after processing draw calls");
    if !renderable.buffers.vertexBuffer then return;
    
    pipeline := *vk.pipelines[pipelineType];
    
    render := New(RenderCommand);
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
			      ifx useTintOverride then tintOverride else renderable.tint, renderable.texture.index, render.buffers.vertexBufferAddress };
    
    camera.isOrthographic = currentCameraProjection;
}

render_command :: (cmdBuffer : VkCommandBuffer, render : *RenderCommand, pipelineLayout : VkPipelineLayout) {
    vkCmdPushConstants(cmdBuffer, pipelineLayout, .VERTEX_BIT, 0, size_of(AllPushConstants), *render.pushConstants);
    
    vkCmdBindIndexBuffer(cmdBuffer, render.buffers.indexBuffer.buffer, 0, .UINT32);
    vkCmdDrawIndexed(cmdBuffer, render.buffers.indexCount, 1, 0, 0, 0);
}

