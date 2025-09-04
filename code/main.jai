/*
Project: Loam
File: main.jai
Author: Brock Salmon
Created: 25MAR2025
*/

IS_DEV :: true;
#if !IS_DEV && OS == .WINDOWS {
    Compiler :: #import "Compiler";
    #run Compiler.set_build_options_dc(.{append_linker_arguments=.["/SUBSYSTEM:windows", "/ENTRY:mainCRTStartup"]});
}

START_WIDTH  :: 1920;
START_HEIGHT :: 1080;
refreshRate  := 60;

testText : *UI_Element;

main :: () {
    #if OS == .WINDOWS {
        Windows.SetProcessDPIAware();
        Windows.timeBeginPeriod(1);
    }

    make_log_file(APP_NAME, .YEAR | .MONTH | .DAY | .HOUR); 
    
    window := create_window(START_WIDTH, START_HEIGHT, APP_NAME);

    init_loam(window, xx START_WIDTH, xx START_HEIGHT);

    refreshRate = get_refresh_rate(window);

    loam.deltaTime = seconds_since_init();
    lastTime := seconds_since_init();

    #if IS_DEV {
	metrics : DebugMetrics;
        #if OS == .ANDROID {
	    fontSize : u32 = 64;
	    build_font_atlas("internal", fontSize, .English, true);	    
	} else {
	    fontSize : u32 = 32;
	    build_font_atlas("internal", fontSize, .English, true);
	}

	{
	    transform := make_transform( .{}, scale = make_vector3(0.75), alignment = .Bottom);
	    text := make_text("Player", "internal", fontSize, transform);
	    testText = make_ui_element(text, false);
	    array_add(*loam.uiElements, testText);
	}
    }

    sprite := make_sprite("test_sprite", make_transform(.{ cast(float) loam.windowWidth * 0.5, cast(float) loam.windowHeight * 0.5, 0 }));
    testSprites : [256] *Sprite;
    for * testSprites {
	it.* = make_sprite("test_sprite", make_transform(.{ cast(float) loam.windowWidth * 0.2 + cast(float) (5 * it_index), cast(float) loam.windowHeight * 0.2 + cast(float) (5 * it_index), 0 }));
    }

    // Input Registration
    move_sprite_left  :: (extraData : *void) { sprite := cast(*Sprite) extraData; sprite.position.x -= cast(float) (100.0 * loam.deltaTime); }
    move_sprite_right :: (extraData : *void) { sprite := cast(*Sprite) extraData; sprite.position.x += cast(float) (100.0 * loam.deltaTime); }
    move_sprite_up    :: (extraData : *void) { sprite := cast(*Sprite) extraData; sprite.position.y += cast(float) (100.0 * loam.deltaTime); }
    move_sprite_down  :: (extraData : *void) { sprite := cast(*Sprite) extraData; sprite.position.y -= cast(float) (100.0 * loam.deltaTime); }

    dpadCenter := Vector2.{200, 200};
    {
	uiSprite := make_sprite("arrow_left", make_transform(.{ dpadCenter.x - 100, dpadCenter.y, 0 }), .{ 1, 1, 1, 0.25 });
	elem := make_ui_element(uiSprite, true, .{ 1, 1, 1, 1 }, activateMode = .WhileDown, activateFunc = move_sprite_left, activateData = sprite);
	array_add(*loam.uiElements, elem);
    }
    {
	uiSprite := make_sprite("arrow_right", make_transform(.{ dpadCenter.x + 100, dpadCenter.y, 0 }), .{ 1, 1, 1, 0.25 });
	elem := make_ui_element(uiSprite, true, .{ 1, 1, 1, 1 }, activateMode = .WhileDown, activateFunc = move_sprite_right, activateData = sprite);
	array_add(*loam.uiElements, elem);
    }
    {
	uiSprite := make_sprite("arrow_up", make_transform(.{ dpadCenter.x, dpadCenter.y + 100, 0 }), .{ 1, 1, 1, 0.25 });
	elem := make_ui_element(uiSprite, true, .{ 1, 1, 1, 1 }, activateMode = .WhileDown, activateFunc = move_sprite_up, activateData = sprite);
	array_add(*loam.uiElements, elem);
    }
    {
	uiSprite := make_sprite("arrow_down", make_transform(.{ dpadCenter.x, dpadCenter.y - 100, 0 }), .{ 1, 1, 1, 0.25 });
	elem := make_ui_element(uiSprite, true, .{ 1, 1, 1, 1 }, activateMode = .WhileDown, activateFunc = move_sprite_down, activateData = sprite);
	array_add(*loam.uiElements, elem);
    }

    #if OS == .WINDOWS {
	move_cam_left  :: (extraData : *void) { loam.sceneCamera.position.x -= cast(float) (50.0 * loam.deltaTime); }
	move_cam_right :: (extraData : *void) { loam.sceneCamera.position.x += cast(float) (50.0 * loam.deltaTime); }
	move_cam_up    :: (extraData : *void) { loam.sceneCamera.position.y += cast(float) (50.0 * loam.deltaTime); }
	move_cam_down  :: (extraData : *void) { loam.sceneCamera.position.y -= cast(float) (50.0 * loam.deltaTime); }

	register_keycode_input(Key_Code.ARROW_LEFT,  .{}, move_cam_left,  null);
	register_keycode_input(Key_Code.ARROW_RIGHT, .{}, move_cam_right, null);
	register_keycode_input(Key_Code.ARROW_UP,    .{}, move_cam_up,    null);
	register_keycode_input(Key_Code.ARROW_DOWN,  .{}, move_cam_down,  null);

	register_keycode_input(#char "A", .{}, move_sprite_left,  sprite);
	register_keycode_input(#char "D", .{}, move_sprite_right, sprite);
	register_keycode_input(#char "W", .{}, move_sprite_up,    sprite);
	register_keycode_input(#char "S", .{}, move_sprite_down,  sprite);
    }

    loam_finish_update();
    
    while loam.running {
	TIMING_FRAME_START();
        update_window_events();
	
	resizes := get_window_resizes();
        for resizes {
	    if it_index == resizes.count - 1 {
		loam.windowWidth = it.width;
		loam.windowHeight = it.height;
		refreshRate = get_refresh_rate(window);
	    }
        }

	if vk.resizeRequested then resize_swapchain();

	vk.currentFrame = get_current_frame();

        for events_this_frame {
            if it.type == {
                case .QUIT; loam.running = false;
		case .KEYBOARD; {
		    // NOTE: If we do have modifier flags then we probably don't want to rrepeat the input, so we can use the raw event
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

	TIMING_MARKER("Events & Input");
	
	loam_start_update();

	TIMING_MARKER("Update Start");
	
	update_pointer_status(window, *loam.mainPointer);
	
	for loam.uiElements {
	    update_ui_element(loam.mainPointer, it);
	}

	#if IS_DEV {
	    for loam.debugUIElements {
		update_ui_element(loam.mainPointer, it);
	    }
	}

	update_text_position(testText.text, sprite.position + .{ 0, 50, 0 });
	
	TIMING_MARKER("Update Recording");

	loam_finish_update();
	
	TIMING_MARKER("Update Finish");

        #if IS_DEV && OS == .WINDOWS {
	    frame_imgui(*metrics);
	    TIMING_MARKER("Handle ImGui");
	}
	
	loam_start_render();
	
	TIMING_MARKER("Render Start");
	
	#if IS_DEV
	{
	    render_debug_ui();
    	    TIMING_MARKER("Render Record (Debug UI)");
	}
	
	add_sprite_render_command(.Sprite, sprite.renderable, sprite.transform);
	
	for testSprites {
	    add_sprite_render_command(.Sprite, it.renderable, it.transform);
	}

	TIMING_MARKER("Render Record (Sprites)");
	
	for loam.uiElements {
	    add_ui_render_command(it);
	}

	TIMING_MARKER("Render Record (UI)");
	
	#if IS_DEV {
	    update_debug_metrics(*metrics);
	}
	
	loam_finish_render();
	
	TIMING_MARKER("Render Finish");
	
	/*
	if vk.vsync {
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

	TIMING_FRAME_END(false);
	
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
