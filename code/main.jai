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
refreshRate  := 60;
deltaTime : float64 = 0;

main :: () {
    #if OS == .WINDOWS {
        Windows.SetProcessDPIAware();
        Windows.timeBeginPeriod(1);
    }

    make_log_file(APP_NAME, .YEAR | .MONTH | .DAY | .HOUR); 
    
    window := create_window(windowWidth, windowHeight, APP_NAME);

    loam := init_loam(window, xx windowWidth, xx windowHeight);

    refreshRate = get_refresh_rate(window);
    
    deltaTime = seconds_since_init();
    lastTime := seconds_since_init();

    #if IS_DEBUG {
	metrics : DebugMetrics;
        #if OS == .ANDROID {
	    frameTimeText = make_text("", loam.defaultFont, 64, make_transform( .{ 10, windowHeight - 10.0, 0 }, scale = make_vector3(0.5), alignment = .Left | .Top ));
	    ramUsageText  = make_text("", loam.defaultFont, 64, make_transform( .{ 10, windowHeight - 40.0, 0 }, scale = make_vector3(0.5), alignment = .Left | .Top ));
	    drawCallText  = make_text("", loam.defaultFont, 64, make_transform( .{ 10, windowHeight - 70.0, 0 }, scale = make_vector3(0.5), alignment = .Left | .Top ));
	} else {
	    frameTimeText = make_text("", loam.defaultFont, 32, make_transform( .{ 10, windowHeight - 10.0, 0 }, scale = make_vector3(0.5), alignment = .Left | .Top ));
	    ramUsageText  = make_text("", loam.defaultFont, 32, make_transform( .{ 10, windowHeight - 30.0, 0 }, scale = make_vector3(0.5), alignment = .Left | .Top ));
	    drawCallText  = make_text("", loam.defaultFont, 32, make_transform( .{ 10, windowHeight - 50.0, 0 }, scale = make_vector3(0.5), alignment = .Left | .Top ));
	}
    }

    sprite := make_sprite(loam, "test_sprite", make_transform(.{ cast(float) windowWidth * 0.5, cast(float) windowHeight * 0.5, 0 }));
    
    while running := true {
        update_window_events();

	resizes := get_window_resizes();
        for resizes {
	    if it_index == resizes.count - 1 {
		windowWidth = it.width;
		windowHeight = it.height;
		refreshRate = get_refresh_rate(window);
	    }
        }

	if loam.vk.resizeRequested then resize_swapchain(loam.vk, loam.camera);
	
        for events_this_frame {
            if it.type == {
                case .QUIT; break running;
            }
        }

	handle_input(loam);

	reset_info_for_rendering(loam);

	#if IS_DEBUG
	{
	    render_debug_stats(loam, *metrics);
	}

	draw_sprite(loam, sprite);
	
	draw_frame(loam);

	if loam.vk.vsync {
	    targetMs := 1.0 / cast(float) refreshRate;
	    msSoFar := (seconds_since_init() - lastTime) * 1000.0;
	    msToWait := targetMs - msSoFar;
	    while msToWait > 0 {
		sleep_milliseconds(1);
		msToWait = targetMs - (seconds_since_init() - lastTime) * 1000.0;
	    }
	}
	
        deltaTime = seconds_since_init() - lastTime;
        lastTime = seconds_since_init();
        
        reset_temporary_storage();

        #if IS_DEBUG {
	    update_debug_metrics(loam, *metrics, deltaTime);

            #if OS != .ANDROID {
		memory_visualizer_per_frame_update();
		//report_memory_leaks();	
	    }
	}
    }

    deinit(loam.assets.directory);
    free(loam.assets.directory);

    free(loam.assets);
    free(loam.vk);
    free(loam.camera);
    free(loam);
}

#load "engine.jai";
