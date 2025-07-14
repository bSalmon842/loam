/*
Project: Loam
File: thread.jai
Author: Brock Salmon
Created: 11JUL2025
*/

ThreadWorkType :: enum {
    UploadToGPU;
}

ThreadWork :: struct {
    type : ThreadWorkType;
    loam : *LoamState;

    union {
	uploadData : UploadToGPU_ThreadData;
    }

    UploadToGPU_ThreadData :: struct {
	indices : [] u32;
	vertices : [] Vertex;
	buffers : *MeshBuffers;
	proc : (*LoamState, [] u32, [] Vertex, *MeshBuffers);
    }
}

ThreadSystemInfo :: struct {
    group : Thread_Group;
    pool : Pool;
    allocator : Allocator;

    workCount : u32;
}

thread_proc :: (group : *Thread_Group, thread : *Thread, workDataRaw : *void) -> Thread_Continue_Status {
    workData := cast(*ThreadWork) workDataRaw;
    loam := workData.loam;

    context.allocator = group.allocator;
    
    if !context.threadVkContext {
	context.threadVkContext = New(VkThreadContext,, group.allocator);

	vkGetDeviceQueue(loam.vk.device, loam.vk.queueFamilyIndices.graphics, context.thread_index, *context.threadVkContext.queue);
	
	cmdPoolCreateInfo := VkCommandPoolCreateInfo.{ .COMMAND_POOL_CREATE_INFO, null, .RESET_COMMAND_BUFFER_BIT, loam.vk.queueFamilyIndices.graphics };
	vkCreateCommandPool(loam.vk.device, *cmdPoolCreateInfo, null, *context.threadVkContext.cmdPool);

	cmdBufferAllocInfo := VkCommandBufferAllocateInfo.{ .COMMAND_BUFFER_ALLOCATE_INFO, null, context.threadVkContext.cmdPool, .PRIMARY, 1 };
	vkAllocateCommandBuffers(loam.vk.device, *cmdBufferAllocInfo, *context.threadVkContext.cmdBuffer);

	fenceCreateInfo := VkFenceCreateInfo.{ .FENCE_CREATE_INFO, null, .SIGNALED_BIT };
	vkCreateFence(loam.vk.device, *fenceCreateInfo, null, *context.threadVkContext.fence);
    }
    
    if #complete workData.type == {
	case .UploadToGPU; {
	    data := workData.uploadData;
	    data.proc(loam, data.indices, data.vertices, data.buffers);
	}
    }
    
    return .CONTINUE;
}

initialise_thread_system :: (system : *ThreadSystemInfo, groupName : string) {
    threadCount := get_number_of_threads_for_device();
    init(*system.group, threadCount, thread_proc);

    system.group.name = groupName;
    system.group.logging = false;

    set_allocators(*system.pool);
    system.allocator.proc = pool_allocator_proc;
    system.allocator.data = *system.pool;

    start(*system.group);
}

add_thread_work :: (system : *ThreadSystemInfo, data : ThreadWork, logTitle : string) {
    work := New(ThreadWork,, system.allocator);
    work.* = data;
    add_work(*system.group, work, logTitle);
    system.workCount += 1;
}

wait_for_thread_work_to_finish :: (system : *ThreadSystemInfo) {
    while system.workCount > 0 {
	workResults := get_completed_work(*system.group);
	system.workCount -= xx workResults.count;
    }
}

get_number_of_threads_for_device :: () -> s32 {
    cpuCount := get_number_of_processors();
    assert(cpuCount > 1);

    if cpuCount > 128 then cpuCount = 128;
    cpuCount /= 2;

    return max(cpuCount-1, 2);
}
