/*
Project: Loam
File: engine.jai
Author: Brock Salmon
Created: 08JUN2025
*/

// TODO: Meshes
// TODO: States for menus, loading, etc
// TODO: Gamepad input

// Compiled Shaders
#if OS == .WINDOWS {
    MESH_VERTEX_SHADER     :: #run compile_glsl_to_spirv("mesh_vertex");
    MESH_FRAGMENT_SHADER   :: #run compile_glsl_to_spirv("mesh_fragment");
    UI_FRAGMENT_SHADER     :: #run compile_glsl_to_spirv("ui_fragment");
    TEXT_FRAGMENT_SHADER   :: #run compile_glsl_to_spirv("text_fragment");
    SPRITE_VERTEX_SHADER   :: #run compile_glsl_to_spirv("sprite_vertex");
    SPRITE_FRAGMENT_SHADER :: #run compile_glsl_to_spirv("sprite_fragment");
} else #if OS == .ANDROID {
    MESH_VERTEX_SHADER     : CompiledShader;
    MESH_FRAGMENT_SHADER   : CompiledShader;
    UI_FRAGMENT_SHADER     : CompiledShader;
    TEXT_FRAGMENT_SHADER   : CompiledShader;
    SPRITE_VERTEX_SHADER   : CompiledShader;
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

    // TODO: Hardcoded cameras probably aren't a good plan
    sceneCamera : *Camera;
    uiCamera : *Camera;
    
    fonts : *Table(string, *FontAtlas);
    
    binds : *InputBinds;
    mainPointer : PointerStatus;
    
    #if IS_DEV {
	debugUIElements : [..] *UI_Element;
    }
    uiElements : [..] *UI_Element;

    activeAudio : [..] *Audio.Sound_Stream;
    
    updateActive : bool;
    renderActive : bool;
    
    windowWidth  : s64;
    windowHeight : s64;
    deltaTime    : float64;
    running      : bool = true;

    // Config
    config : Config;
}

Config :: struct {
    audioDevice  : Audio.Output_Device;
    masterVolume : float;
    bgVolume     : float;
    sfxVolume    : float;

    vsync : bool;
}

init_loam :: (window : Window_Type, initialWidth : float, initialHeight : float) {
    #if OS == .ANDROID {
	MESH_VERTEX_SHADER   = load_spirv_for_android("mesh_vertex");
	MESH_FRAGMENT_SHADER = load_spirv_for_android("mesh_fragment");
	UI_FRAGMENT_SHADER   = load_spirv_for_android("ui_fragment");
	TEXT_FRAGMENT_SHADER = load_spirv_for_android("text_fragment");
	SPRITE_VERTEX_SHADER = load_spirv_for_android("sprite_vertex");
	SPRITE_FRAGMENT_SHADER = load_spirv_for_android("sprite_fragment");
    }
    
    _loam := New(LoamState);
    #if IS_DEV then this_allocation_is_not_a_leak(_loam);
    
    context.loam = _loam;
    loam = context.loam;
    
    // NOTE: Set update to true so we can setup everything for initialisation
    loam.updateActive = true;
    
    loam.assets = New(AssetState);
    #if IS_DEV then this_allocation_is_not_a_leak(loam.assets);
    init_assets(loam.assets);
    
    init_config();
    
    if !Audio.sound_player_init(.{ output_device = *loam.config.audioDevice }) then log(.FATAL, "Failed to initialise Sound Player");
    
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
    
    loam.vk = New(Vk);
    #if IS_DEV then this_allocation_is_not_a_leak(loam.vk);
    init_vk(window);

    #if IS_DEV && OS == .WINDOWS {
	init_imgui(window);
    }
    
    loam.fonts = New(Table(string, *FontAtlas));
    init(loam.fonts);
    
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

init_config :: () {
    // TODO: Load config and get audio device
    
    devices := Audio.get_devices();
    loam.config.audioDevice = devices[0];
    
    loam.config.masterVolume = 0.2;
    Audio.set_master_volume(loam.config.masterVolume);
    loam.config.bgVolume = 1.0;
    loam.config.sfxVolume = 1.0;

    loam.config.vsync = false;
}

loam_start_update :: () {
    // TODO: We probably don't need to do this once we have section guards
    for vk.updateCommands {
	if it then log(.FATAL, "Update Command array was not cleared, either loam_finish_update was never called, or the array has failed to clear");
    }

    loam.updateActive = true;
}

loam_finish_update :: () {
    process_update_commands();

    for * vk.updateCommands {
	if it.* {
	    vkFreeCommandBuffers(vk.device, vk.updateCmdPool, 1, *it.*.cmdBuffer);
	    cleanup_buffers(it.*.bufferCleanup);
	    free(it.*.data);
	    free(it.*);
	    it.* = null;
	}
    }

    loam.updateActive = false;

    update_audio();
}

loam_start_render :: () {
    cleanup_single_frame_images();
    cleanup_single_frame_buffers();

    loam.renderActive = true;
}

loam_finish_render :: () {
    update_bindless_descriptor_textures();
    TIMING_MARKER("Update Bindless Descriptor");
    draw_frame();
    TIMING_MARKER("Render Draw");

    for * vk.pipelines {
	if it.isSpritePipeline {
	    for * it.sprites.array {
		it.* = .{};
	    }
	    it.sprites.count = 0;
	} else {
	    for * it.renderCommands {
		if it.* {
		    free(it.*);
		    it.* = null;
		}
	    }
	}
    }

    loam.renderActive = false;
}

render_debug_ui :: () {
    for loam.debugUIElements {
	add_ui_render_command(it);
    }
}

#load "assets.jai";
#load "audio.jai";
#load "camera.jai";
#load "font.jai";
#if IS_DEV then #load "imgui.jai";
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
Audio :: #import "Sound_Player_bs842";
#import "VMA";
#import "Vulkan_1_3";
#if IS_DEV && OS == .WINDOWS then ImGui :: #import "ImGui_1_9";

