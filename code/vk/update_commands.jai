/*
Project: Loam
File: update_commands.jai
Author: Brock Salmon
Created: 19JUL2025
*/

BuffersToCleanup :: struct {
    array  : [] *AllocatedBufferInfo;
    memory : *void;
}
pack_buffers_for_cleanup :: (buffers : .. *AllocatedBufferInfo) -> *BuffersToCleanup {
    cleanup := New(BuffersToCleanup);
    cleanup.array, cleanup.memory = NewArray(buffers.count, *AllocatedBufferInfo);
    for buffers {
	cleanup.array[it_index] = it;
    }
    
    return cleanup;
}

UpdateCommand :: struct {
    cmdBuffer     : VkCommandBuffer;
    bufferCleanup : *BuffersToCleanup;
}

// Add a Vulkan immediate command to be run during the update phase which are then queued once
UpdateCommandFunc :: #type (VkCommandBuffer, *void);
add_update_command :: (func : UpdateCommandFunc, data : *void, update : *UpdateCommand) {
    //lock(loam.mutexes[MutexUsage.UpdateCommand]);
    //defer unlock(loam.mutexes[MutexUsage.UpdateCommand]);
    
    cmdBufferAllocInfo := VkCommandBufferAllocateInfo.{ .COMMAND_BUFFER_ALLOCATE_INFO, null, vk.updateCmdPool, .PRIMARY, 1 };
    check_vk(vkAllocateCommandBuffers(vk.device, *cmdBufferAllocInfo, *update.cmdBuffer), "Failed to allocate Command Buffer for Update Command");
    
    cmdBufferBeginInfo := VkCommandBufferBeginInfo.{ .COMMAND_BUFFER_BEGIN_INFO, null, .ONE_TIME_SUBMIT_BIT, null };
    check_vk(vkBeginCommandBuffer(update.cmdBuffer, *cmdBufferBeginInfo), "Failed to begin Command Buffer for Update Command");
    
    func(update.cmdBuffer, data);
    
    check_vk(vkEndCommandBuffer(update.cmdBuffer), "Failed to end Command Buffer for Update Command");
}

process_update_commands :: () {
    fenceCreateInfo : VkFenceCreateInfo;
    fence : VkFence;
    check_vk(vkCreateFence(vk.device, *fenceCreateInfo, null, *fence), "Failed to create Fence for Update Commands");

    cmdBufferSubmitInfos, infoMemory := NewArray(vk.updateCommands.count, VkCommandBufferSubmitInfo);
    for vk.updateCommands {
	cmdBufferSubmitInfos[it_index] = VkCommandBufferSubmitInfo.{ .COMMAND_BUFFER_SUBMIT_INFO, null, it.cmdBuffer, 0 };
    }
    
    submitInfo := VkSubmitInfo2.{ .SUBMIT_INFO_2, null, 0, 0, null, cast(u32) cmdBufferSubmitInfos.count, cmdBufferSubmitInfos.data, 0, null };
    check_vk(vkQueueSubmit2(vk.graphicsQueue, 1, *submitInfo, fence), "Failed to submit Queue for Update Commands");
    
    check_vk(vkWaitForFences(vk.device, 1, *fence, VK_TRUE, FENCE_WAIT_TIME), "Failed to wait for fence for Update Commands");
    vkDestroyFence(vk.device, fence, null);

    free(infoMemory);
}

