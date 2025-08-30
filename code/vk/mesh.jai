/*
Project: Loam
File: vk/mesh.jai
Author: Brock Salmon
Created: 20MAY2025
*/

Vertex :: struct {
    position : Vector3 #align 16;
    normal   : Vector3 #align 16;
    uv       : Vector2 #align 16;
    colour   := Vector4.{1,1,1,1} #align 16;
}

GPUBufferInfo :: struct {
    buffer        : *AllocatedBufferInfo;
    bufferAddress : VkDeviceAddress;
}

GPUBuffers :: struct {
    indexBuffer         : *AllocatedBufferInfo;
    indexCount          : u32;
    union {
	vertex : GPUBufferInfo;
	sprite : GPUBufferInfo;
    }
}

MeshCopyData :: struct {
    vertexBufferSize : u64;
    indexBufferSize  : u64;
    stagingBuffer    : *AllocatedBufferInfo;
    buffers          : *GPUBuffers;
}

DEFAULT_PLANE_INDICES :: u32.[0, 1, 2,
		              2, 1, 3];
is_default_plane_indices :: (arr : [] u32) -> bool {
    if arr.count != DEFAULT_PLANE_INDICES.count then return false;
    for arr { if it != DEFAULT_PLANE_INDICES[it_index] then return false; }
    
    return true;
}

upload_mesh_command :: (indices : [] u32, vertices : [] Vertex, buffers : *GPUBuffers) {
    indexBufferSize := cast(u64) (indices.count * size_of(u32));
    vertexBufferSize := cast(u64) (vertices.count * size_of(Vertex));
    
    buffers.indexBuffer  = ifx is_default_plane_indices(indices) then vk.defaultPlaneIndexBuffer else create_vk_buffer(indexBufferSize, .INDEX_BUFFER_BIT | .TRANSFER_DST_BIT);
    buffers.indexCount   = cast(u32) indices.count;
    
    buffers.vertex.buffer = create_vk_buffer(vertexBufferSize, .STORAGE_BUFFER_BIT | .TRANSFER_DST_BIT | .SHADER_DEVICE_ADDRESS_BIT);
    deviceAddressInfo := VkBufferDeviceAddressInfo.{ .BUFFER_DEVICE_ADDRESS_INFO, null, buffers.vertex.buffer.buffer };
    buffers.vertex.bufferAddress = vkGetBufferDeviceAddress(vk.device, *deviceAddressInfo);
    
    // Set up staging buffer and copy to buffers
    stagingBuffer := create_vk_buffer(indexBufferSize + vertexBufferSize, .TRANSFER_SRC_BIT);
    
    memcpy(stagingBuffer.allocationInfo.pMappedData, cast(*u8) vertices.data, cast(s64) vertexBufferSize);
    memcpy(cast(*u8) stagingBuffer.allocationInfo.pMappedData + vertexBufferSize, cast(*u8) indices.data, cast(s64) indexBufferSize);
    
    gpu_mesh_copy :: (cmdBuffer : VkCommandBuffer, data : *void) {
	meshData := cast(*MeshCopyData) data;

	vertexCopy := VkBufferCopy.{ 0, 0, meshData.vertexBufferSize };
	vkCmdCopyBuffer(cmdBuffer, meshData.stagingBuffer.buffer, meshData.buffers.vertex.buffer.buffer, 1, *vertexCopy);
	
	indexCopy := VkBufferCopy.{ meshData.vertexBufferSize, 0, meshData.indexBufferSize };
	vkCmdCopyBuffer(cmdBuffer, meshData.stagingBuffer.buffer, meshData.buffers.indexBuffer.buffer, 1, *indexCopy);
    }
    
    meshData := New(MeshCopyData);
    meshData.* = .{ vertexBufferSize, indexBufferSize, stagingBuffer, buffers };
    
    buffersToCleanup : *BuffersToCleanup;
    if is_default_plane_indices(indices) {
	buffersToCleanup = pack_buffers_for_cleanup(stagingBuffer);
    } else {
	buffersToCleanup = pack_buffers_for_cleanup(stagingBuffer, buffers.indexBuffer);
    }

    add_update_command(gpu_mesh_copy, meshData, buffersToCleanup);
}
