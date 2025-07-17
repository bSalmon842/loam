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

START_WIDTH  :: 1920;
START_HEIGHT :: 1080;
refreshRate  := 60;

main :: () {
    #if OS == .WINDOWS {
        Windows.SetProcessDPIAware();
        Windows.timeBeginPeriod(1);
    }

    make_log_file(APP_NAME, .YEAR | .MONTH | .DAY | .HOUR); 
    
    window := create_window(START_WIDTH, START_HEIGHT, APP_NAME);

    loam := init_loam(window, xx START_WIDTH, xx START_HEIGHT);

    refreshRate = get_refresh_rate(window);

    initialise_thread_system(loam, *loam.threadSystem, "Loam Thread System");
    
    loam.deltaTime = seconds_since_init();
    lastTime := seconds_since_init();

    #if IS_DEBUG {
	metrics : DebugMetrics;
        #if OS == .ANDROID {
	    fontSize : u32 = 64;
	    frameTimePosition := Vector3.{ 10, loam.windowHeight - 10.0, 0 };
	    ramUsagePosition  := Vector3.{ 10, loam.windowHeight - 40.0, 0 };
	    drawCallPosition  := Vector3.{ 10, loam.windowHeight - 70.0, 0 };
	    
	} else {
	    fontSize : u32 = 32;
    	    frameTimePosition := Vector3.{ 10, loam.windowHeight - 10.0, 0 };
	    ramUsagePosition  := Vector3.{ 10, loam.windowHeight - 30.0, 0 };
	    drawCallPosition  := Vector3.{ 10, loam.windowHeight - 50.0, 0 };
	}

	{
	    text := make_text(loam, "", loam.defaultFont, fontSize, make_transform( frameTimePosition, scale = make_vector3(0.5), alignment = .Left | .Top ));
	    frameTimeText = make_ui_element(loam, text, true, .{ 0, 0.5, 1, 1 });
	}
	{
	    text := make_text(loam, "", loam.defaultFont, fontSize, make_transform( ramUsagePosition, scale = make_vector3(0.5), alignment = .Left | .Top ));
	    ramUsageText = make_ui_element(loam, text, true, .{ 1, 0, 1, 1 });
	}
	{
	    text := make_text(loam, "", loam.defaultFont, fontSize, make_transform( drawCallPosition, scale = make_vector3(0.5), alignment = .Left | .Top ));
	    drawCallText = make_ui_element(loam, text, false);
	}
	
	array_add(*loam.debugUIElements, frameTimeText);
	array_add(*loam.debugUIElements, ramUsageText);
	array_add(*loam.debugUIElements, drawCallText);
    }

    sprite := make_sprite(loam, "test_sprite", make_transform(.{ cast(float) loam.windowWidth * 0.5, cast(float) loam.windowHeight * 0.5, 0 }));
    testSprites : [256] *Sprite;
    for * testSprites {
	it.* = make_sprite(loam, "test_sprite", make_transform(.{ cast(float) loam.windowWidth * 0.2 + cast(float) (5 * it_index), cast(float) loam.windowHeight * 0.2 + cast(float) (5 * it_index), 0 }));
    }

    // Input Registration
    move_sprite_left  :: (loam : *LoamState, extraData : *void) { sprite := cast(*Sprite) extraData; sprite.position.x -= cast(float) (100.0 * loam.deltaTime); }
    move_sprite_right :: (loam : *LoamState, extraData : *void) { sprite := cast(*Sprite) extraData; sprite.position.x += cast(float) (100.0 * loam.deltaTime); }
    move_sprite_up    :: (loam : *LoamState, extraData : *void) { sprite := cast(*Sprite) extraData; sprite.position.y += cast(float) (100.0 * loam.deltaTime); }
    move_sprite_down  :: (loam : *LoamState, extraData : *void) { sprite := cast(*Sprite) extraData; sprite.position.y -= cast(float) (100.0 * loam.deltaTime); }

    dpadCenter := Vector2.{200, 200};
    {
	uiSprite := make_sprite(loam, "arrow_left", make_transform(.{ dpadCenter.x - 100, dpadCenter.y, 0 }), .{ 1, 1, 1, 0.25 });
	elem := make_ui_element(loam, uiSprite, true, .{ 1, 1, 1, 1 }, activateMode = .WhileDown, activateFunc = move_sprite_left, activateData = sprite);
	array_add(*loam.uiElements, elem);
    }
    {
	uiSprite := make_sprite(loam, "arrow_right", make_transform(.{ dpadCenter.x + 100, dpadCenter.y, 0 }), .{ 1, 1, 1, 0.25 });
	elem := make_ui_element(loam, uiSprite, true, .{ 1, 1, 1, 1 }, activateMode = .WhileDown, activateFunc = move_sprite_right, activateData = sprite);
	array_add(*loam.uiElements, elem);
    }
    {
	uiSprite := make_sprite(loam, "arrow_up", make_transform(.{ dpadCenter.x, dpadCenter.y + 100, 0 }), .{ 1, 1, 1, 0.25 });
	elem := make_ui_element(loam, uiSprite, true, .{ 1, 1, 1, 1 }, activateMode = .WhileDown, activateFunc = move_sprite_up, activateData = sprite);
	array_add(*loam.uiElements, elem);
    }
    {
	uiSprite := make_sprite(loam, "arrow_down", make_transform(.{ dpadCenter.x, dpadCenter.y - 100, 0 }), .{ 1, 1, 1, 0.25 });
	elem := make_ui_element(loam, uiSprite, true, .{ 1, 1, 1, 1 }, activateMode = .WhileDown, activateFunc = move_sprite_down, activateData = sprite);
	array_add(*loam.uiElements, elem);
    }

    #if OS == .WINDOWS {
	move_cam_left  :: (loam : *LoamState, extraData : *void) { loam.sceneCamera.position.x -= cast(float) (50.0 * loam.deltaTime); }
	move_cam_right :: (loam : *LoamState, extraData : *void) { loam.sceneCamera.position.x += cast(float) (50.0 * loam.deltaTime); }
	move_cam_up    :: (loam : *LoamState, extraData : *void) { loam.sceneCamera.position.y += cast(float) (50.0 * loam.deltaTime); }
	move_cam_down  :: (loam : *LoamState, extraData : *void) { loam.sceneCamera.position.y -= cast(float) (50.0 * loam.deltaTime); }

	register_keycode_input(loam, Key_Code.ARROW_LEFT,  .{}, move_cam_left,  null);
	register_keycode_input(loam, Key_Code.ARROW_RIGHT, .{}, move_cam_right, null);
	register_keycode_input(loam, Key_Code.ARROW_UP,    .{}, move_cam_up,    null);
	register_keycode_input(loam, Key_Code.ARROW_DOWN,  .{}, move_cam_down,  null);

	register_keycode_input(loam, #char "A", .{}, move_sprite_left,  sprite);
	register_keycode_input(loam, #char "D", .{}, move_sprite_right, sprite);
	register_keycode_input(loam, #char "W", .{}, move_sprite_up,    sprite);
	register_keycode_input(loam, #char "S", .{}, move_sprite_down,  sprite);
    }

    timing : [6] float64;
    
    while loam.running {
	tickStart := seconds_since_init() - lastTime;
        update_window_events();
	
	resizes := get_window_resizes();
        for resizes {
	    if it_index == resizes.count - 1 {
		loam.windowWidth = it.width;
		loam.windowHeight = it.height;
		refreshRate = get_refresh_rate(window);
	    }
        }

	if loam.vk.resizeRequested then resize_swapchain(loam);

	loam.vk.currentFrame = get_current_frame(loam.vk);
	
        for events_this_frame {
            if it.type == {
                case .QUIT; loam.running = false;
		case .KEYBOARD; {
		    // NOTE: If we do have modifier flags then we probably don't want to rrepeat the input, so we can use the raw event
		    if it.key_pressed && it.modifier_flags.packed != 0 {
			handle_keycode_input(loam, it.key_code, it.modifier_flags);
		    }
		}
            }
        }

	// NOTE: If we don't have any modifier flags then we might want to repeat the input (such as for movement, etc) so we use input_button_states
	for input_button_states {
	    if it & .DOWN {
		handle_keycode_input(loam, cast(Key_Code) it_index, .{});
	    }
	}
	
	#if IS_DEBUG {
	    update_debug_metrics(loam, *metrics);
	    wait_for_thread_work_to_finish(*loam.threadSystem);
	    update_debug_ui_regions();
	}

	update_pointer_status(loam, window, *loam.mainPointer);

	for loam.uiElements {
	    update_ui_element(loam, loam.mainPointer, it);
	}

	#if IS_DEBUG {
	    for loam.debugUIElements {
		update_ui_element(loam, loam.mainPointer, it);
	    }
	}

	timing[0] = (seconds_since_init() - lastTime) - (tickStart);

	reset_info_for_rendering(loam);

	timing[1] = (seconds_since_init() - lastTime) - (timing[0] + tickStart);
	
	#if IS_DEBUG
	{
	    render_debug_ui(loam, *metrics);
	}

	add_render_command(loam, .Sprite, loam.sceneCamera, *sprite.renderable, sprite.transform);
	for testSprites {
	    add_render_command(loam, .Sprite, loam.sceneCamera, *it.renderable, it.transform);
	}

	for loam.uiElements {
	    add_ui_render_command(loam, it);
	}

	timing[2] = (seconds_since_init() - lastTime) - (timing[1] + timing[0] + tickStart);
	
	draw_frame(loam);

	timing[3] = (seconds_since_init() - lastTime) - (timing[2] + timing[1] + timing[0] + tickStart);

	/*
	if loam.vk.vsync {
	    targetMs := 1.0 / cast(float) refreshRate;
	    msSoFar := (seconds_since_init() - lastTime) * 1000.0;
	    msToWait := targetMs - msSoFar;
	    while msToWait > 0 {
		sleep_milliseconds(1);
		msToWait = targetMs - (seconds_since_init() - lastTime) * 1000.0;
	    }
	}
*/

        loam.deltaTime = seconds_since_init() - lastTime;
        lastTime = seconds_since_init();
	for * timing {
	    it.* *= 1000.0;
	}
	deltaMs := loam.deltaTime * 1000.0;
	print("Events, Input, & Update: % (%\%)\nReset: % (%\%)\nDraw Record: % (%\%)\nDraw Execute: % (%\%)\nTotal Frame Time: % (%)\n\n",
	      timing[0], (timing[0] / deltaMs) * 100.0, timing[1], (timing[1] / deltaMs) * 100.0, timing[2], (timing[2] / deltaMs) * 100.0,
	      timing[3], (timing[3] / deltaMs) * 100.0, deltaMs, cast(u32) (1.0 / loam.deltaTime + 1.0));
        
        reset_temporary_storage();

	/*
        #if IS_DEBUG {
            #if OS != .ANDROID {
		memory_visualizer_per_frame_update();
		//report_memory_leaks();	
	    }
	}
        */
    }

    deinit(loam.assets.directory);
}

#load "engine.jai";
