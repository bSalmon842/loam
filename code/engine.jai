/*
Project: Loam
File: engine.jai
Author: Brock Salmon
Created: 08JUN2025
*/

// TODO: Meshes
// TODO: Audio
// TODO: A struct for holding data all renderables will need (visibility, etc) (Currently this is Renderable2D in render.jai)
// TODO: States for menus, loading, etc
// TODO: Gamepad input

// Compiled Shaders
#if OS == .WINDOWS {
    MESH_VERTEX_SHADER   :: #run compile_glsl_to_spirv("mesh_vertex");
    MESH_FRAGMENT_SHADER :: #run compile_glsl_to_spirv("mesh_fragment");
    UI_VERTEX_SHADER     :: #run compile_glsl_to_spirv("ui_vertex");
    UI_FRAGMENT_SHADER   :: #run compile_glsl_to_spirv("ui_fragment");
    TEXT_FRAGMENT_SHADER :: #run compile_glsl_to_spirv("text_fragment");
    SPRITE_FRAGMENT_SHADER :: #run compile_glsl_to_spirv("sprite_fragment");
} else #if OS == .ANDROID {
    MESH_VERTEX_SHADER   : CompiledShader;
    MESH_FRAGMENT_SHADER : CompiledShader;
    UI_VERTEX_SHADER     : CompiledShader;
    UI_FRAGMENT_SHADER   : CompiledShader;
    TEXT_FRAGMENT_SHADER : CompiledShader;
    SPRITE_FRAGMENT_SHADER : CompiledShader;
}

// Add the engine to the context so we don't have to pass it everywhere, then add global alias' for some main structures
#add_context loam : *LoamState;
loam : *LoamState;

#add_context vk : *Vk;
vk : *Vk;

LoamState :: struct {
    assets : *AssetState;
    vk : *Vk;
    
    threadCount : s32;
    renderingThread : *Thread;
    updateThread    : *Thread;
    
    mutexes : [#run enum_highest_value(MutexUsage) + 1] *Mutex;
    
    sceneCamera : *Camera;
    uiCamera : *Camera;
    
    fonts : *Table(string, *FontAtlas);
    
    resources : *ResourcePools;
    
    binds : *InputBinds;
    mainPointer : PointerStatus;
    
    #if IS_DEV {
	debugUIElements : [..] *UI_Element;
    }
    uiElements : [..] *UI_Element;
    
    windowWidth  : s64;
    windowHeight : s64;
    deltaTime    : float64;
    running      : bool = true;
}

init_loam :: (window : Window_Type, initialWidth : float, initialHeight : float) {
    #if OS == .ANDROID {
	MESH_VERTEX_SHADER   = load_spirv_for_android("mesh_vertex");
	MESH_FRAGMENT_SHADER = load_spirv_for_android("mesh_fragment");
	UI_VERTEX_SHADER     = load_spirv_for_android("ui_vertex");
	UI_FRAGMENT_SHADER   = load_spirv_for_android("ui_fragment");
	TEXT_FRAGMENT_SHADER = load_spirv_for_android("text_fragment");
	SPRITE_FRAGMENT_SHADER = load_spirv_for_android("sprite_fragment");
    }
    
    _loam := New(LoamState);
    #if IS_DEV then this_allocation_is_not_a_leak(_loam);
    
    context.loam = _loam;
    loam = context.loam;

    loam.resources = New(ResourcePools);
    #if IS_DEV then this_allocation_is_not_a_leak(loam.resources);
    
    loam.assets = New(AssetState);
    #if IS_DEV then this_allocation_is_not_a_leak(loam.assets);
    loam.assets.directory = load_asset_directory();

    loam.sceneCamera = New(Camera);
    #if IS_DEV then this_allocation_is_not_a_leak(loam.sceneCamera);
    loam.sceneCamera.verticalFOV = 80.0;
    loam.sceneCamera.dimensions = .{ initialWidth, initialHeight };
    loam.sceneCamera.position.z = -2;
    loam.sceneCamera.isOrthographic = false;

    loam.uiCamera = New(Camera);
    #if IS_DEV then this_allocation_is_not_a_leak(loam.uiCamera);
    loam.uiCamera.dimensions = .{ initialWidth, initialHeight };
    loam.uiCamera.isOrthographic = true;
    
    loam.threadCount = get_number_of_threads_for_device();
    log(.INFO, tprint("Threads found on device: %\n", loam.threadCount));
    loam.renderingThread = create_thread("Loam_Render", rendering_thread_proc);
    loam.updateThread    = create_thread("Loam_Update", update_thread_proc);
    
    for * loam.mutexes {
	it.* = New(Mutex);
	init(it.*, enum_names(MutexUsage)[it_index], cast(s32) (it_index + 1));
    }
    
    loam.vk = New(Vk);
    #if IS_DEV then this_allocation_is_not_a_leak(loam.vk);
    init_vk(window);
    
    loam.fonts = New(Table(string, *FontAtlas));
    init(loam.fonts);
    
    build_font_atlas("internal", 32, .English, true);
    build_font_atlas("internal", 64, .English, true);
    
    loam.binds = New(InputBinds);
    
    loam.windowWidth = xx initialWidth;
    loam.windowHeight = xx initialHeight;

    #if OS == .WINDOWS {
	quit_game :: (extraData : *void) {
	    loam.running = false;
	}
	register_keycode_input(Key_Code.F4, .{ alt_pressed = true }, quit_game, null);
    }
}

loam_start_update :: () {
    if vk.updateCommands.count > 0 then log(.FATAL, "Update Command array was not cleared, either loam_finish_update was never called, or the array has failed to clear");
}

loam_finish_update :: () {
    wait_for_work_to_finish_on_thread(loam.updateThread);
    process_update_commands();

    for vk.updateCommands {
	vkFreeCommandBuffers(vk.device, vk.updateCmdPool, 1, *it.cmdBuffer);
	for it.bufferCleanup.array {
	    destroy_vk_buffer(it);
	}
	free(it.bufferCleanup.memory);
	free(it.bufferCleanup);
	free(it);
    }
    array_reset(*vk.updateCommands);
}

loam_start_render :: () {
    cleanup_single_frame_images();
    cleanup_single_frame_buffers();

    for * vk.pipelines {
	for it.renderCommands {
	    free(it);
	}
	array_reset(*it.renderCommands);
    }
}

loam_finish_render :: () {
    wait_for_work_to_finish_on_thread(loam.renderingThread);
    TIMING_MARKER("Render Wait");
    update_bindless_descriptor_textures();
    TIMING_MARKER("Descriptor Update");
    draw_frame();
    TIMING_MARKER("Render Draw");
}

render_debug_ui :: () {
    for loam.debugUIElements {
	add_ui_render_command(it);
    }
}

#load "assets.jai";
#load "camera.jai";
#load "font.jai";
#load "input.jai";
#load "math.jai";
#load "metrics.jai";
#load "sprite.jai";
#load "text.jai";
#load "thread.jai";
#load "transform.jai";
#load "utility.jai";
#load "ui.jai";
#load "vk/vk.jai";

#import "Atomics";
#import "Basic"() (MEMORY_DEBUGGER = OS == .WINDOWS);
#import "File";
#import "File_Utilities";
#import "freetype-2.12.1";
#import "Hash_Table";
#import "Input";
#import "Math";
#import "Print_Color"() (USE_ANSI_CODES_ON_WINDOWS=true);
#import "Process";
#import "Reflection";
Simp :: #import "Simp";
#import "String";
#import "System";
#import "Thread";
#import "Unicode";
#import "Window_Creation";

#if OS == .WINDOWS {
    Windows :: #import "Windows";
    WindowsUTF8 :: #import "Windows_Utf8";
    
    WindowsE :: #import "WindowsExtras";
} else #if OS == .LINUX {
    X11 :: #import "X11";
} else #if OS == .ANDROID {
    #import "Android"()(main);
    #import "Android/File";
    #import "Android/Jni";
    #import "POSIX";
}

// BS_Modules
#import "ktx";
#import "Logger" (IS_DEV);
#import "VMA";
#import "Vulkan_1_3";
