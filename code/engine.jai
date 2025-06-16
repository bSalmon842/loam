/*
Project: Loam
File: engine.jai
Author: Brock Salmon
Created: 08JUN2025
*/

LoamState :: struct {
    assets : *AssetState;
    vk : *Vk;

    camera : *Camera;
}

init_loam :: (window : Window_Type, initialWidth : float, initialHeight : float) -> *LoamState {
    loam := New(LoamState);

    loam.assets = New(AssetState);
    loam.assets.directory = load_asset_directory();
    loam.assets.cacheSentinel.prev = *loam.assets.cacheSentinel;
    loam.assets.cacheSentinel.next = *loam.assets.cacheSentinel;

    loam.vk = New(Vk);
    init_vk(loam, window);

    loam.camera = New(Camera);
    loam.camera.verticalFOV = 80.0;
    loam.camera.dimensions = .{ initialWidth, initialHeight };
    
    return loam;
}

handle_input :: (loam : *LoamState) {
    for input_button_states {
	handle_keyboard_input(loam, it, it_index);
    }
    handle_mouse_input(loam);
}

handle_keyboard_input :: (loam : *LoamState, keyState : Key_Current_State, keyCode : s64) {
    // TODO: Functors from game
    if keyState & .DOWN {
	if keyCode == {
	    case #char "A"; loam.camera.position.x -= cast(float) (5.0 * deltaTime);
	    case #char "D"; loam.camera.position.x += cast(float) (5.0 * deltaTime);

	    case #char "Q"; loam.camera.position.y += cast(float) (5.0 * deltaTime);
	    case #char "Z"; loam.camera.position.y -= cast(float) (5.0 * deltaTime);
	    
	    case #char "W"; loam.camera.position.z += cast(float) (5.0 * deltaTime);
	    case #char "S"; loam.camera.position.z -= cast(float) (5.0 * deltaTime);
	}
    }
}

handle_mouse_input :: (loam : *LoamState) {
    // TODO: Functors from game
}

#load "assets.jai";
#load "camera.jai";
#load "math.jai";
#load "utility.jai";
#load "vk/vk.jai";

#import "Basic"() (MEMORY_DEBUGGER = IS_DEBUG);
#import "File";
#import "File_Utilities";
#import "Hash_Table";
#import "Input";
#import "Math";
#import "Print_Color"() (USE_ANSI_CODES_ON_WINDOWS=true);
#import "Process";
#import "Reflection";
Simp :: #import "Simp";
#import "String";
#import "Window_Creation";

#if OS == .WINDOWS {
    Windows :: #import "Windows";
} else #if OS == .LINUX {
    X11 :: #import "X11";
} else #if OS == .ANDROID {
    #import "Android"()(main);
    #import "Android/File";
}

// BS_Modules
#import "ktx";
#import "Logger" (IS_DEBUG);
#import "VMA";
#import "Vulkan_1_3";
