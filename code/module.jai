/*
Project: Loam
File: module.jai
Author: Brock Salmon
Created: 08JUN2025
*/

#module_parameters(APP_NAME := "", ASSET_CODE := "", IS_DEV := false);
#run assert(APP_NAME.count > 0, "Need to set APP_NAME in loam's module parameters");

// TODO: Meshes

// Compiled Shaders
#if OS == .WINDOWS {
    MESH_VERTEX_SHADER          :: #run compile_glsl_to_spirv("mesh_vertex");
    MESH_FRAGMENT_SHADER        :: #run compile_glsl_to_spirv("mesh_fragment");
    UI_FRAGMENT_SHADER          :: #run compile_glsl_to_spirv("ui_fragment");
    TEXT_FRAGMENT_SHADER        :: #run compile_glsl_to_spirv("text_fragment");
    SPRITE_VERTEX_SHADER        :: #run compile_glsl_to_spirv("sprite_vertex");
    SPRITE_FRAGMENT_SHADER      :: #run compile_glsl_to_spirv("sprite_fragment");
    SPRITE_RECT_FRAGMENT_SHADER :: #run compile_glsl_to_spirv("sprite_rect_fragment");

    #if IS_DEV {
	BOX_COLLIDER_VERTEX_SHADER   :: #run compile_glsl_to_spirv("box_collider_vertex");
	BOX_COLLIDER_FRAGMENT_SHADER :: #run compile_glsl_to_spirv("box_collider_fragment");
    }

    IMGUI_VERT :: #run compile_glsl_to_spirv("imgui_vertex");
    IMGUI_FRAG :: #run compile_glsl_to_spirv("imgui_fragment");
} else #if OS == .ANDROID {
    MESH_VERTEX_SHADER          : CompiledShader;
    MESH_FRAGMENT_SHADER        : CompiledShader;
    UI_FRAGMENT_SHADER          : CompiledShader;
    TEXT_FRAGMENT_SHADER        : CompiledShader;
    SPRITE_VERTEX_SHADER        : CompiledShader;
    SPRITE_FRAGMENT_SHADER      : CompiledShader;
    SPRITE_RECT_FRAGMENT_SHADER : CompiledShader;

    #if IS_DEV {
	BOX_COLLIDER_VERTEX_SHADER   : CompiledShader;
	BOX_COLLIDER_FRAGMENT_SHADER : CompiledShader;
    }
}

// Add the engine to the context so we don't have to pass it everywhere, then add global alias' for some main structures
#add_context loam : *LoamState;
loam : *LoamState;

#add_context vk : *Vk;
vk : *Vk;

LoamState :: struct {
    assets : *AssetState;
    vk : *Vk;

    gameplayState : GameplayState;
    
    threadCount : s32;
    
    cameras : *CameraMap;
    activeGameCamera : *Camera;
    
    fonts : *Table(string, *FontAtlas);
    
    keybinds : *KeybindMap;
    input : *InputState;
    
    uiElements : [..] *UI_Element;
    
    audioDevice : Audio.Output_Device;
    activeAudio : [..] *Audio.Sound_Stream;
    
    updateActive : bool;
    renderActive : bool;

    window       : *SDL.Window;
    windowWidth  : s32;
    windowHeight : s32;
    refreshRate  : float32;
    deltaTime    : float64;
    lastTime     : float64;
    running      : bool = true;

    // Splash Screens
    splashScreens : [..] SplashScreen;
    splashIndex : u32 = 0;
    splashTimer : float64 = 0;
    
    // Config
    config : Config;

    // Entities
    entities : [#run (enum_highest_value(EntityUpdateRate) + 1)] EntityMap;

    #if IS_DEV {
	debugUIElements : [..] *UI_Element;
	metrics : DebugMetrics;
    }
}

init_loam :: (initialWidth : s32, initialHeight : s32) {
    if APP_NAME.count == 0 {
	log(.FATAL, "No app name was set");
    }

    if ASSET_CODE.count == 0 || ASSET_CODE.count > 4 || ASSET_CODE == "LOAM" {
	log(.FATAL, "Invalid asset code, code cannot be \"LOAM\", nor be more than 4 characters");
    }
    
    #if OS == .ANDROID {
	MESH_VERTEX_SHADER          = load_spirv_for_android("mesh_vertex");
	MESH_FRAGMENT_SHADER        = load_spirv_for_android("mesh_fragment");
	UI_FRAGMENT_SHADER          = load_spirv_for_android("ui_fragment");
	TEXT_FRAGMENT_SHADER        = load_spirv_for_android("text_fragment");
	SPRITE_VERTEX_SHADER        = load_spirv_for_android("sprite_vertex");
	SPRITE_FRAGMENT_SHADER      = load_spirv_for_android("sprite_fragment");
	SPRITE_RECT_FRAGMENT_SHADER = load_spirv_for_android("sprite_rect_fragment");
	#if IS_DEV {
	    BOX_COLLIDER_VERTEX_SHADER   = load_spirv_for_android("box_collider_vertex");
	    BOX_COLLIDER_FRAGMENT_SHADER = load_spirv_for_android("box_collider_fragment");
	}
    }
    
    make_log_file(APP_NAME, .YEAR | .MONTH | .DAY | .HOUR);
    
    _loam := New(LoamState);
    #if IS_DEV then this_allocation_is_not_a_leak(_loam);
    
    context.loam = _loam;
    loam = context.loam;
    
    time := current_time_consensus();
    context.random_state = .{ time.low | 1, cast,no_check(u64) time.high };
    
    // NOTE: Set update to true so we can setup everything for initialisation
    loam.updateActive = true;
    
    loam.assets = New(AssetState);
    #if IS_DEV then this_allocation_is_not_a_leak(loam.assets);
    init_assets(loam.assets, ASSET_CODE);
    
    init_config();
    
    loam.audioDevice = get_audio_device_from_name(loam.config.audioDeviceName);
    if !Audio.sound_player_init(.{ output_device = *loam.audioDevice, update_from_a_thread = (OS != .ANDROID) }) then log(.FATAL, "Failed to initialise Sound Player");
    
    SDL.init(.VIDEO | .JOYSTICK | .HAPTIC | .GAMEPAD);
    loam.window = SDL.create_window(APP_NAME, initialWidth, initialHeight, .VULKAN);
    if !loam.window {
	log(.FATAL, "Failed to create window with SDL error: %", to_string(SDL.get_error()));
    }

    loam.windowWidth = initialWidth;
    loam.windowHeight = initialHeight;
    loam.refreshRate = SDL.get_current_display_mode(SDL.get_display_for_window(loam.window)).refresh_rate;

    loam.cameras = New(CameraMap);
    add_camera("UI", 0, .{});
    
    loam.threadCount = get_number_of_threads_for_device();
    log(.INFO, "Threads found on device: %", loam.threadCount);
    
    loam.vk = New(Vk);
    #if IS_DEV then this_allocation_is_not_a_leak(loam.vk);
    init_vk();

    #if IS_DEV && OS == .WINDOWS {
	init_imgui();
    }
    
    loam.fonts = New(Table(string, *FontAtlas));
    init(loam.fonts);

    loam.keybinds = init_keybinds();
    loam.input = New(InputState);
    loam.input.activeType = .Keyboard_Mouse;
    
    loam.deltaTime = seconds_since_init();
    loam.lastTime = seconds_since_init();

    loam.gameplayState = .Splash;

    array_add(*loam.splashScreens, .{ get_resource(ImageResource, "__loam_splash"), get_resource(AudioResource, "__loam_splash_audio"), .{0.05, 0.05, 0.05, 1.0} });
}

loam_start_update :: () {
    // INPUT HANDLING
    loam.input.mouseWheel = .{};
    
    event : SDL.Event;
    while SDL.poll_event(*event) {
	if event.type == {
	    case .QUIT; loam.running = false;

	    case .WINDOW_RESIZED; {
		loam.windowWidth  = event.window.data1;
		loam.windowHeight = event.window.data2;
	    } #through;
	    case .WINDOW_MOVED; {
		loam.refreshRate = SDL.get_current_display_mode(SDL.get_display_for_window(loam.window)).refresh_rate;
		print("%\n", loam.refreshRate);
	    }

	    case .MOUSE_WHEEL; {
		loam.input.mouseWheel = .{ event.wheel.x, event.wheel.y };
		if event.wheel.direction == .FLIPPED then loam.input.mouseWheel *= -1.0;
	    }
	}
	
	update_input(event);
	ImGui.ImplSDL3_ProcessEvent(cast(*ImGui.SDL_Event) *event);
    }

    if vk.resizeRequested then resize_swapchain();
    
    // OTHER UPDATING
    update_audio();
    
    for vk.updateCommands {
	if it then log(.FATAL, "Update Command array was not cleared, either loam_finish_update/loam_finish_init was never called, or the array has failed to clear");
    }

    vk.currentFrame = get_current_frame();

    #if IS_DEV {
	for loam.entities[EntityUpdateRate.Full] {
	    it.collider.colliding = false;
	}
    }

    loam.updateActive = true;
}

loam_finish_update :: () {
    update_entities();
    
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
}

// NOTE: This is just syntactic sugar so games don't need a random finish_update just before the main loop starts
loam_finish_init :: () {
    loam_finish_update();
}

loam_start_render :: () {
    loam.renderActive = true;

    #if IS_DEV && OS == .WINDOWS {
	frame_imgui(*loam.metrics);
    }
}

loam_finish_render :: () {
    #if IS_DEV {
	update_debug_metrics(*loam.metrics);
    }
    
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
	} else if it.isBoxColliderPipeline {
	    for * it.boxColliders.array {
		it.* = .{};
	    }
	    it.boxColliders.count = 0;
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

loam_handle_timing :: () {
    if loam.config.vsync {
	targetMs := (1.0 / cast(float) loam.refreshRate) * 1000.0;
	msSoFar := (seconds_since_init() - loam.lastTime) * 1000.0;
	msToWait := targetMs - msSoFar;
	while msToWait > 0 {
	    if msToWait > 1 then sleep_milliseconds(1);
	    msToWait = targetMs - (seconds_since_init() - loam.lastTime) * 1000.0;
	}
    }
    
    loam.deltaTime = seconds_since_init() - loam.lastTime;
    loam.lastTime = seconds_since_init();
}

render_debug_ui :: () {
    for loam.debugUIElements {
	add_ui_render_command(it);
    }
}

EXTRA_IMPORTS :: #string DONE
#import "Basic";
#import "File";
#import "File_Utilities";
#import "freetype";
#import "Hash_Table";
#import "Math";
#import "Print_Color";
#import "Process";
#import "Random";
#import "Reflection";
Simp :: #import "Simp";
#import "String";
#import "System";
#import "Thread";
#import "Unicode";

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

#import "ktx";
#import "Logger" (IS_DEV);
#import "lz4_bs842";
SDL :: #import "SDL3";
Audio :: #import "Sound_Player_bs842";
#import "VMA";
#import "Vulkan_1_3";
#if IS_DEV && OS == .WINDOWS then ImGui :: #import "ImGui_1_9";
DONE

#load "assets.jai";
#load "audio.jai";
#load "camera.jai";
#load "collision.jai";
#load "config.jai";
#load "entity.jai";
#load "font.jai";
#if IS_DEV then #load "imgui.jai";
#load "input.jai";
#load "json.jai";
#load "math.jai";
#load "metrics.jai";
#load "resources.jai";
#load "shared_asset_info.jai";
#load "sprite.jai";
#load "state.jai";
#load "text.jai";
#load "thread.jai";
#load "transform.jai";
#load "utility.jai";
#load "ui.jai";
#load "vk/vk.jai";

#scope_module
#import "Basic";
#import "File";
#import "File_Utilities";
#import "freetype";
#import "Hash_Table";
#import "Math";
#import "Print_Color";
#import "Process";
#import "Random";
#import "Reflection";
Simp :: #import "Simp";
#import "String";
#import "System";
#import "Thread";
#import "Unicode";

#if OS == .WINDOWS {
    Windows :: #import "Windows";
    WindowsUTF8 :: #import "Windows_Utf8";
    WindowsE :: #import "WindowsExtras";
} else #if OS == .LINUX {
    X11 :: #import "X11";
} else #if OS == .ANDROID {
    #import "Android";
    //#import "Android/File";
    #import "Android/Jni";
    #import "POSIX";
}

// BS_Modules
#import "ktx";
#import "Logger"(IS_DEV);
#import "lz4_bs842";
SDL :: #import "SDL3";
Audio :: #import "Sound_Player_bs842";
#import "VMA";
#import "Vulkan_1_3";
#if IS_DEV && OS == .WINDOWS then ImGui :: #import "ImGui_1_9";

