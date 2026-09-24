 /*
Project: Loam
File: module.jai
Author: Brock Salmon
Created: 08JUN2025
*/

#module_parameters(APP_NAME := "", ASSET_CODE := "", IS_DEV := false, VERSION := "");
#run assert(APP_NAME.count > 0, "Need to set APP_NAME in loam's module parameters");

// TODO: print stdout in game

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
	GRID_VERTEX_SHADER           :: #run compile_glsl_to_spirv("grid_vertex");
	GRID_FRAGMENT_SHADER         :: #run compile_glsl_to_spirv("grid_fragment");
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
	GRID_VERTEX_SHADER           : CompiledShader;
	GRID_FRAGMENT_SHADER         : CompiledShader;
    }
}

#if IS_DEV {
    VERSION_TEXT :: #run sprint("V:% (DEV)", VERSION);
} else {
    VERSION_TEXT :: #run sprint("V:%", VERSION);
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
    
    ambientLight := Vector4.{ 1, 1, 1, 0.1 };
    lights : [MAX_LIGHTS_IN_SCENE] Light;

    #if IS_DEV {
	debugUIElements : [..] *UI_Element;
	metrics : DebugMetrics;

	devViewActive : bool = true;
	drawWorldGrid : bool = true;
	drawLights    : bool = true;
	debugCameraMode : bool;
	debugCameraHold : *Camera;
	debugKeybinds : *KeybindMap;
    }
}

init_loam :: (initialWidth : s32, initialHeight : s32) {
    if APP_NAME.count == 0 {
	log(.FATAL, "No app name was set");
    }

    if ASSET_CODE.count == 0 || ASSET_CODE.count > 4 || ASSET_CODE == "LOAM" {
	log(.FATAL, "Invalid asset code, code cannot be \"LOAM\", nor be more than 4 characters");
    }

    #if OS == .WINDOWS {
        Windows.SetProcessDPIAware();
        Windows.timeBeginPeriod(1);
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
    context.random_state = { time.low | 1, cast,no_check(u64) time.high };
    
    // NOTE: Set update to true so we can setup everything for initialisation
    loam.updateActive = true;
    
    loam.assets = New(AssetState);
    #if IS_DEV then this_allocation_is_not_a_leak(loam.assets);
    init_assets(loam.assets, ASSET_CODE);
    
    init_config();
    
    loam.audioDevice = get_audio_device_from_name(loam.config.audioDeviceName);
    if !Audio.sound_player_init({ output_device = *loam.audioDevice, update_from_a_thread = (OS != .ANDROID) }) then log(.FATAL, "Failed to initialise Sound Player");

    SDL.set_hint(SDL.HINT_ORIENTATIONS, "LandscapeLeft LandscapeRight");
    SDL.init(.VIDEO | .JOYSTICK | .HAPTIC | .GAMEPAD);
    
    flags := SDL.Window_Flags.VULKAN;
    #if OS == .ANDROID then flags |= .FULLSCREEN;
    loam.window = SDL.create_window(APP_NAME, initialWidth, initialHeight, flags);
    if !loam.window {
	log(.FATAL, "Failed to create window with SDL error: %", to_string(SDL.get_error()));
    }
    
    loam.refreshRate = SDL.get_current_display_mode(SDL.get_display_for_window(loam.window)).refresh_rate;
    SDL.get_window_size_in_pixels(loam.window, *loam.windowWidth, *loam.windowHeight);
    #if OS == .ANDROID {
	while (loam.windowWidth < loam.windowHeight) {
	    SDL.get_window_size_in_pixels(loam.window, *loam.windowWidth, *loam.windowHeight);
	}
    }
    
    loam.cameras = New(CameraMap);
    add_camera("UI", 0, {});
    loam.activeGameCamera = add_camera("Game", 60, .{}, ortho=false);
    
    loam.threadCount = get_number_of_threads_for_device();
    log(.INFO, "Threads found on device: %", loam.threadCount);
    
    loam.vk = New(Vk);
    #if IS_DEV then this_allocation_is_not_a_leak(loam.vk);
    init_vk();

    #if IS_DEV && OS == .WINDOWS {
	init_imgui();
    }
    
    loam.fonts = New(Table(string, *FontAtlas));

    loam.keybinds = init_keybinds();
    loam.input = New(InputState);
    loam.input.activeType = .Keyboard_Mouse;
    
    loam.deltaTime = seconds_since_init();
    loam.lastTime = seconds_since_init();

    loam.gameplayState = .Splash;

    array_add(*loam.splashScreens, { get_resource(ImageResource, "__loam_splash"), get_resource(AudioResource, "__loam_splash_audio"), {0.05, 0.05, 0.05, 1.0} });

    #if IS_DEV {
	fontSize : u32 = 32;
	build_font_atlas("__loam_internal", fontSize, .English);
	build_font_atlas("__loam_internal_mono", fontSize, .English);

	add_camera("Debug", 60, {}, ortho=false);
	loam.debugKeybinds = init_debug_keybinds();
    }
}

loam_start_update :: () {
    // INPUT HANDLING
    array_reset(*loam.input.touch);
    loam.input.mouseWheel = {};
    loam.input.relativeMouseMove = {};
    
    event : SDL.Event;
    while SDL.poll_event(*event) {
	if event.type == {
	    case .TERMINATING; #through;
	    case .QUIT; loam.running = false;
	    
	    case .WINDOW_RESIZED; {
		loam.windowWidth  = event.window.data1;
		loam.windowHeight = event.window.data2;
	    } #through;
	    case .WINDOW_MOVED; {
		loam.refreshRate = SDL.get_current_display_mode(SDL.get_display_for_window(loam.window)).refresh_rate;
		vk.recreateSwapchain = true;
		print("%\n", loam.refreshRate);
	    }
	    
	    // Android Events
	    case .LOW_MEMORY; {
		#if OS == .ANDROID {
		    log(.WARN, "Device is running low on available memory");
		    // TODO: Handle low memory
		}
	    }
	}

	update_input(event);
	
	#if OS != .ANDROID {
	    ImGui.ImplSDL3_ProcessEvent(cast(*ImGui.SDL_Event) *event);
	}
    }

    // Engine Controls
    #if IS_DEV {
	if get_input("Debug Camera Mode", true) > 0.5 {
	    invert_bool(*loam.debugCameraMode);
	}
	if loam.debugCameraMode {
	    debugCamera := get_camera("Debug");
	    if !loam.debugCameraHold || loam.debugCameraHold == debugCamera {
		debugCamera.position = loam.activeGameCamera.position;
		debugCamera.orientation = loam.activeGameCamera.orientation;
		
		loam.debugCameraHold = loam.activeGameCamera;
		loam.activeGameCamera = debugCamera;
	    } else {
		if SDL.get_mod_state() & .ALT == 0 {
		    SDL.set_window_relative_mouse_mode(loam.window, true);
		    // Orientation
		    DEBUG_ROTATION_SPEED :: 10.0;
		    euler := quaternion_to_euler(debugCamera.orientation);
		    pitch := get_input("Debug Camera Pitch", true) * DEBUG_ROTATION_SPEED * cast(float32) loam.deltaTime;
		    yaw := get_input("Debug Camera Yaw", true) * DEBUG_ROTATION_SPEED * cast(float32) loam.deltaTime;
		    
		    euler.x += pitch;
		    pitchLimit := PI/2 - 0.025;
		    Clamp(*euler.x, -pitchLimit, pitchLimit);
		    
		    euler.y += yaw;
		    euler.y = fmod_cycling(euler.y, TAU);
		    
		    qYaw, qPitch : Quaternion;
		    set_from_axis_and_angle(*qYaw, .{ 0, 1, 0 }, euler.y);
		    set_from_axis_and_angle(*qPitch, .{ 1, 0, 0 }, euler.x);
		    debugCamera.orientation = qYaw * qPitch;
		    
		    // Movement
		    DEBUG_MOVE_SPEED :: 10.0;
		    x := get_input("Debug Camera X", true);
		    y := get_input("Debug Camera Y", true);
		    z := get_input("Debug Camera Z", true);
		    move := Vector3.{ x, y, z };
		    normalize(*move);

		    forward := normalize(rotate({ 0, 0, 1 }, debugCamera.orientation));
		    debugCamera.position += (forward * move.z) * DEBUG_MOVE_SPEED * loam.deltaTime;

		    right := -cross(forward, { 0, 1, 0 });
		    debugCamera.position += (right * move.x) * DEBUG_MOVE_SPEED * loam.deltaTime;

		    up := cross(forward, right);
		    debugCamera.position += (up * move.y) * DEBUG_MOVE_SPEED * loam.deltaTime;
		} else {
		    SDL.set_window_relative_mouse_mode(loam.window, false);
		}
	    }
	} else if loam.debugCameraHold {
	    loam.activeGameCamera = loam.debugCameraHold;
	    loam.debugCameraHold = null;
	}
    }
    
    if vk.recreateSwapchain {
	if vk.recreateSurface {
	    recreate_surface();
	}
	recreate_swapchain();
    }
    
    // OTHER UPDATING
    update_audio();
    
    for vk.updateCommands {
	if it then log(.FATAL, "Update Command array was not cleared, either loam_finish_update/loam_finish_init was never called, or the array has failed to clear");
    }

    vk.currentFrame = get_current_frame();

    #if IS_DEV {
	for loam.entities[EntityUpdateRate.Full] {
	    if it.collider then it.collider.colliding = false;
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

loam_finish_init :: () {
    #if IS_DEV {
        text := make_text(VERSION_TEXT, "__loam_internal_mono", 32, make_transform());
	text.alignment = .Bottom | .Right;
	versionText := make_ui_element(text);
	array_add(*loam.uiElements, versionText);
	
	update_text_position(text, .{ xx loam.windowWidth - 75.0, 10.0, 0 });
    }
    
    loam_finish_update();
}

loam_start_render :: () {
    #if IS_DEV {
	#if OS == .WINDOWS {
	    frame_imgui(*loam.metrics);
	}
    }
    
    for loam.uiElements {
	if it.activeStates & loam.gameplayState {
	    add_ui_render_command(it);
	}
    }

    #if IS_DEV {
	if loam.drawLights && loam.gameplayState != .Splash {
	    for loam.lights {
		if it.intensity > EPSILON32 {
		    add_box_collider_render_command(make_vector3(0.1), make_transform(it.position, it.orientation), false);
		}
	    }
	}
    }
}

loam_finish_render :: () {
    #if IS_DEV {
	update_debug_metrics(*loam.metrics);
    }

    update_world_data(loam.activeGameCamera, loam.ambientLight);
    //destroy_vk_buffer(vk.worldDataBuffer);
    if !vk.worldDataBuffer then vk.worldDataBuffer = create_vk_buffer(size_of(GraphicsWorldData), .UNIFORM_BUFFER_BIT);
    memcpy(vk.worldDataBuffer.allocationInfo.pMappedData, *vk.worldData, size_of(GraphicsWorldData));
    update_bindless_descriptor_world_data();

    update_bindless_descriptor_textures();
    TIMING_MARKER("Update Bindless Descriptor");
    draw_frame();
    TIMING_MARKER("Render Draw");

    for * vk.pipelines {
	if it.isSpritePipeline {
	    for * it.sprites.array {
		it.* = {};
	    }
	    it.sprites.count = 0;
	} else if it.isBoxColliderPipeline {
	    for * it.boxColliders.array {
		it.* = {};
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
}

#import "gltf_parser";
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
#load "file.jai";
#load "font.jai";
#if IS_DEV then #load "imgui.jai";
#load "input.jai";
#load "json.jai";
#load "lighting.jai";
#load "material.jai";
#load "math.jai";
#load "metrics.jai";
#load "model.jai";
#load "resources.jai";
#load "shapes.jai";
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
}

// BS_Modules
#import "gltf_parser";
#import "ktx";
#import "Logger"(IS_DEV);
#import "lz4_bs842";
SDL :: #import "SDL3";
Audio :: #import "Sound_Player_bs842";
#import "stb_image";
#import "VMA";
#import "Vulkan_1_3";
#if IS_DEV && OS == .WINDOWS then ImGui :: #import "ImGui_1_9";

