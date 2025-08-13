/*
Project: Loam
File: thread.jai
Author: Brock Salmon
Created: 11JUL2025
*/

// NOTE: This enum is ordered by priority to have a thread for, if we don't have enough threads, types towards the end of the enum will not be handled on a separate thread
ThreadWorkType :: enum {
    // Audio;
    AddRenderCommand;
    AddUpdateCommand;
}

MutexUsage :: enum {
    ThreadWorkChange;
    UpdateCommand;
    RenderCommand;
}

ThreadWork :: struct {
    type : ThreadWorkType;

    next : *ThreadWork;
    prev : *ThreadWork;
    
    union {
	renderCommandData : *AddRenderCommand_ThreadData;
	updateCommandData : *AddUpdateCommand_ThreadData;
    }
    
    AddRenderCommand_ThreadData :: struct {
	pipeline : *RenderingPipelineInfo;
	render : *RenderCommand;
	camera : *Camera;
	renderable : *Renderable;
	transform : Transform;
	useTintOverride : bool;
	tintOverride : Vector4;
    }

    AddUpdateCommand_ThreadData :: struct {
	func           : UpdateCommandFunc;
	data           : *void;
	update         : *UpdateCommand;
    }
}

ThreadWorkQueue :: struct {
    sentinel : ThreadWork;
    count : u32;
}

WorkChangeStatus :: enum {
    Add;
    Remove;
}

add_or_remove_work :: (change : WorkChangeStatus, work : *ThreadWork) {
    lock(loam.mutexes[MutexUsage.ThreadWorkChange]);
    defer unlock(loam.mutexes[MutexUsage.ThreadWorkChange]);

    thread : *Thread;

    if #complete work.type == {
	case .AddRenderCommand; thread = loam.renderingThread;
	case .AddUpdateCommand; thread = loam.updateThread;
    }
    
    queue := cast(*ThreadWorkQueue) thread.data;
    
    if #complete change == {
	case .Add; {
	    queue.sentinel.prev.next = work;
	    work.prev = queue.sentinel.prev;
	    
	    queue.sentinel.prev = work;
	    work.next = *queue.sentinel;

	    queue.count += 1;
	}
	
	case .Remove; {
	    work.prev.next = work.next;
	    work.next.prev = work.prev;
	    
	    if #complete work.type == {
		case .AddRenderCommand; free(work.renderCommandData);
		case .AddUpdateCommand; free(work.updateCommandData);
	    }
	    
	    work.* = .{};
	    free(work);
	    queue.count -= 1;
	}
    }
}

create_thread :: (name : string, thread_proc : Thread_Proc) -> *Thread {
    thread := New(Thread);
    #if IS_DEV then this_allocation_is_not_a_leak(thread);
    thread.starting_context.loam = context.loam;
    thread.starting_context.vk = context.vk;
    thread_init(thread, thread_proc);
    thread_start(thread);

#if OS == .WINDOWS {
    WindowsE.SetThreadDescription(thread.windows_thread, WindowsUTF8.utf8_to_wide(name,, temp));
}

    queue := New(ThreadWorkQueue);
    queue.sentinel.next = *queue.sentinel;
    queue.sentinel.prev = *queue.sentinel;
    thread.data = queue;

    return thread;
}

rendering_thread_proc :: (thread : *Thread) -> s64 {
    queue := cast(*ThreadWorkQueue) thread.data;
    while true {
	if queue.count > 0 {
	    currentWork := queue.sentinel.next;
	    if currentWork != *queue.sentinel {
		render := currentWork.renderCommandData;
		add_render_command_on_thread(render.pipeline, render.render, render.camera, render.renderable, render.transform, render.useTintOverride, render.tintOverride);
		
		add_or_remove_work(.Remove, currentWork);
	    }
	}
    }
    
    return 0;
}

update_thread_proc :: (thread : *Thread) -> s64 {
    queue := cast(*ThreadWorkQueue) thread.data;
    while true {
	if queue.count > 0 {
	    currentWork := queue.sentinel.next;
	    if currentWork != *queue.sentinel {
		update := currentWork.updateCommandData;
		add_update_command(update.func, update.data, update.update);

		add_or_remove_work(.Remove, currentWork);
	    }
	}
    }
    
    return 0;
}

add_render_command_work :: (pipelineType : PipelineType, camera : *Camera, renderable : *Renderable, transform : Transform,
			    useTintOverride : bool = false, tintOverride : Vector4 = DEFAULT_TEXTURE_TINT) {
    if !renderable.buffers then return;
    work := New(ThreadWork);
    work.type = .AddRenderCommand;
    work.renderCommandData = New(ThreadWork.AddRenderCommand_ThreadData);
    pipeline := *vk.pipelines[pipelineType];
    render := New(RenderCommand);
    render.buffers = renderable.buffers;
    array_add(*pipeline.renderCommands, render);
    work.renderCommandData.* = .{ pipeline, render, camera, renderable, transform, useTintOverride, tintOverride };
    add_or_remove_work(.Add, work);
}

add_update_command_work :: (func : UpdateCommandFunc, data : *void, buffersToCleanup : *BuffersToCleanup) {
    work := New(ThreadWork);
    work.type = .AddUpdateCommand;
    work.updateCommandData = New(ThreadWork.AddUpdateCommand_ThreadData);
    update := New(UpdateCommand);
    update.bufferCleanup = buffersToCleanup;
    array_add(*vk.updateCommands, update);
    work.updateCommandData.* = .{ func, data, update };
    add_or_remove_work(.Add, work);
}

get_number_of_threads_for_device :: () -> s32 {
    cpuCount := get_number_of_processors();
    assert(cpuCount > 1);

    if cpuCount > 64 then cpuCount = 64;    
    cpuCount = max(cpuCount-1, 2);
    
    return cpuCount;
}

wait_for_work_to_finish_on_thread :: (thread : *Thread) {
    TIMING_SCOPE();
    queue := cast(*ThreadWorkQueue) thread.data;
    while queue.count > 0 {}
}
