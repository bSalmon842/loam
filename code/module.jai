/*
Project: Loam
File: module.jai
Author: Brock Salmon
Created: 08JUN2025
*/

#module_parameters(APP_NAME := "", IS_DEV := false);
#run assert(APP_NAME.count > 0, "Need to set APP_NAME in loam's module parameters");

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

    gameplayState : GameplayState;
    
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

    audioDevice : Audio.Output_Device;
    activeAudio : [..] *Audio.Sound_Stream;
    
    updateActive : bool;
    renderActive : bool;
    
    windowWidth  : s64;
    windowHeight : s64;
    refreshRate  : u32;
    deltaTime    : float64;
    lastTime     : float64;
    running      : bool = true;

    // Splash Screens
    splashScreens : [..] SplashScreen;
    splashIndex : u32 = 0;
    splashTimer : float64 = 0;

    // Config
    config : Config;
}

init_loam :: (window : Window_Type, initialWidth : float, initialHeight : float) {
    if APP_NAME.count == 0 {
        #if OS == .WINDOWS {
	    Windows.MessageBoxA(window, "No app name was set, remember to call #run set_app_name", "Initialisation Error", Windows.MB_OK | Windows.MB_ICONERROR);
	} else #if OS == .ANDROID {
	    
	} else #if OS == .LINUX {
	    X11.x_message_box(X11.None, text, "No app name was set, remember to call #run set_app_name", .ST_OK);
	}

	exit(0);
    }
    
    #if OS == .ANDROID {
	MESH_VERTEX_SHADER   = load_spirv_for_android("mesh_vertex");
	MESH_FRAGMENT_SHADER = load_spirv_for_android("mesh_fragment");
	UI_FRAGMENT_SHADER   = load_spirv_for_android("ui_fragment");
	TEXT_FRAGMENT_SHADER = load_spirv_for_android("text_fragment");
	SPRITE_VERTEX_SHADER = load_spirv_for_android("sprite_vertex");
	SPRITE_FRAGMENT_SHADER = load_spirv_for_android("sprite_fragment");
    }
    
    make_log_file(APP_NAME, .YEAR | .MONTH | .DAY | .HOUR);
    
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

    loam.audioDevice = get_audio_device_from_name(loam.config.audioDeviceName);
    if !Audio.sound_player_init(.{ output_device = *loam.audioDevice }) then log(.FATAL, "Failed to initialise Sound Player");
    
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
    loam.refreshRate = get_refresh_rate(window);
    loam.deltaTime = seconds_since_init();
    loam.lastTime = seconds_since_init();

    loam.gameplayState = .Splash;

    array_add(*loam.splashScreens, .{ get_resource(ImageResource, "loam_splash", true), null, .{0.05, 0.05, 0.05, 1.0} });
    
    // Setup core inputs
    quit_game :: (args : .. Any) {
	loam.running = false;
    }
    skip_splash :: (args : ..Any) {
	transition_state(.Splash, .Playing);
    }
    register_keycode_input(Key_Code.MOUSE_BUTTON_LEFT, .{}, .Splash, skip_splash);
    #if OS == .WINDOWS || OS == .LINUX {
	register_keycode_input(Key_Code.F4, .{ alt_pressed = true }, .All, quit_game);
	register_keycode_input(Key_Code.SPACEBAR, .{}, .Splash, skip_splash);
    }
}

loam_start_update :: () {
    for vk.updateCommands {
	if it then log(.FATAL, "Update Command array was not cleared, either loam_finish_update was never called, or the array has failed to clear");
    }

    vk.currentFrame = get_current_frame();

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

loam_handle_input :: (window : Window_Type) {
    update_window_events();
    
    resizes := get_window_resizes();
    for resizes {
	if it_index == resizes.count - 1 {
	    loam.windowWidth = it.width;
	    loam.windowHeight = it.height;
	    loam.refreshRate = get_refresh_rate(window);
	}
    }

    if vk.resizeRequested then resize_swapchain();
    
    for events_this_frame {
        if it.type == {
            case .QUIT; loam.running = false;
	    case .KEYBOARD; {
		// NOTE: If we do have modifier flags then we probably don't want to repeat the input, so we can use the raw event
		if it.key_pressed && it.modifier_flags.packed != 0 {
		    handle_keycode_input(it.key_code, it.modifier_flags);
		}
	    }
        }
    }
    
    // NOTE: If we don't have any modifier flags then we might want to repeat the input (such as for movement, etc) so we use input_button_states
    for input_button_states {
	if it & .DOWN {
	    handle_keycode_input(cast(Key_Code) it_index, .{});
	}
    }
    
    update_pointer_status(window, *loam.mainPointer);
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
#import "Hash_Table";
#import "Input";
#import "Math";
#import "Print_Color";
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

#import "ktx";
#import "Logger" (IS_DEV);
Audio :: #import "Sound_Player_bs842";
#import "VMA";
#import "Vulkan_1_3";
#if IS_DEV && OS == .WINDOWS then ImGui :: #import "ImGui_1_9";
DONE

#load "assets.jai";
#load "audio.jai";
#load "camera.jai";
#load "config.jai";
#load "font.jai";
#if IS_DEV then #load "imgui.jai";
#load "input.jai";
#load "math.jai";
#load "metrics.jai";
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
#import "freetype-2.12.1";
#import "Hash_Table";
#import "Input";
#import "Math";
#import "Print_Color";
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
    #import "Android";
    #import "Android/File";
    #import "Android/Jni";
    #import "POSIX";
}

// BS_Modules
#import "ktx";
#import "Logger"(IS_DEV);
Audio :: #import "Sound_Player_bs842";
#import "VMA";
#import "Vulkan_1_3";
#if IS_DEV && OS == .WINDOWS then ImGui :: #import "ImGui_1_9";

