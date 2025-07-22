/*
Project: Loam
File: thread.jai
Author: Brock Salmon
Created: 11JUL2025
*/

// TODO: Render commands

// NOTE: This enum is ordered by priority to have a thread for, if we don't have enough threads, types towards the end of the enum will not be handled on a separate thread
ThreadWorkType :: enum {
    // Audio;
    AddRenderCommand;
    AddUpdateCommand;
}

ThreadWork :: struct {
    type : ThreadWorkType;

    union {
	renderCommandData : AddRenderCommand_ThreadData;
	updateCommandData : AddUpdateCommand_ThreadData;
    }
    
    AddRenderCommand_ThreadData :: struct {
	pipelineType : PipelineType;
	camera : *Camera;
	renderable : *Renderable;
	transform : Transform;
	useTintOverride : bool;
	tintOverride : Vector4;
	
	proc : (*LoamState, PipelineType, *Camera, *Renderable, Transform, bool, Vector4);
    }

    AddUpdateCommand_ThreadData :: struct {
	
    }
}

create_thread :: (thread_proc : Thread_Proc) -> *Thread {
    thread := New(Thread);
    #if IS_DEBUG then this_allocation_is_not_a_leak(thread);
    thread.starting_context.loam = context.loam;
    thread.starting_context.vk = context.vk;
    thread_init(thread, thread_proc);
    thread_start(thread);

    return thread;
}

rendering_thread_proc :: (thread : *Thread) -> s64 {
    print_color("YAY THREAD % (%, %)\n", context.thread_index, context.loam, context.vk, color=.HI_BLUE);
    return 0;
}

get_number_of_threads_for_device :: () -> s32 {
    cpuCount := get_number_of_processors();
    assert(cpuCount > 1);

    if cpuCount > 64 then cpuCount = 64;    
    cpuCount = max(cpuCount-1, 2);
    
    return cpuCount;
}
