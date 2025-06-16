/*
Project: Loam
File: main.jai
Author: Brock Salmon
Created: 25MAR2025
*/

IS_DEBUG :: true;
#if !IS_DEBUG && OS == .WINDOWS {
    Compiler :: #import "Compiler";
    #run Compiler.set_build_options_dc(.{append_linker_arguments=.["/SUBSYSTEM:windows", "/ENTRY:mainCRTStartup"]});
}

windowWidth  := 1920;
windowHeight := 1080;
deltaTime : float64 = 0;

// Compiled Shaders
#if OS == .WINDOWS {
    MESH_VERTEX_SHADER   :: #run compile_glsl_to_spirv("mesh_vertex");
    MESH_FRAGMENT_SHADER :: #run compile_glsl_to_spirv("mesh_fragment");
} else #if OS == .ANDROID {
    MESH_VERTEX_SHADER   : CompiledShader;
    MESH_FRAGMENT_SHADER : CompiledShader;
}

main :: () {
    #if OS == .WINDOWS {
        Windows.SetProcessDPIAware();
        Windows.timeBeginPeriod(1);
    } else #if OS == .ANDROID {
	MESH_VERTEX_SHADER   = load_spirv_for_android("mesh_vertex");
	MESH_FRAGMENT_SHADER = load_spirv_for_android("mesh_fragment");
    }

    make_log_file(APP_NAME, .YEAR | .MONTH | .DAY | .HOUR); 
    
    window := create_window(windowWidth, windowHeight, APP_NAME);

    loam := init_loam(window, xx windowWidth, xx windowHeight);
    
    deltaTime = seconds_since_init();
    lastTime := seconds_since_init();
    while running := true {
        update_window_events();
        
        for get_window_resizes() {	
            windowWidth, windowHeight = Simp.get_render_dimensions(it.window);
        }

	if loam.vk.resizeRequested then resize_swapchain(loam.vk);
	
        for events_this_frame {
            if it.type == {
                case .QUIT; break running;
            }
        }

	handle_input(loam);

	draw_frame(loam);
	
        deltaTime = seconds_since_init() - lastTime;
        lastTime = seconds_since_init();
        
        reset_temporary_storage();

	#if IS_DEBUG {
	    memory_visualizer_per_frame_update();
	}
    }

    deinit(loam.assets.directory);
    free(loam.assets.directory);
}

#load "engine.jai";
