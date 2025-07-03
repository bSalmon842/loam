/*
Project: Loam
File: engine.jai
Author: Brock Salmon
Created: 08JUN2025
*/

// TODO: Input
// TODO: Meshes
// TODO: Better render calls (DrawSprite, DrawMesh, etc.)
// TODO: Audio
// TODO: UI (Debug & Game)

// Compiled Shaders
#if OS == .WINDOWS {
    MESH_VERTEX_SHADER      :: #run compile_glsl_to_spirv("mesh_vertex");
    MESH_FRAGMENT_SHADER    :: #run compile_glsl_to_spirv("mesh_fragment");
    UI_VERTEX_SHADER        :: #run compile_glsl_to_spirv("ui_vertex");
    UI_FRAGMENT_SHADER      :: #run compile_glsl_to_spirv("ui_fragment");
    UI_TEXT_FRAGMENT_SHADER :: #run compile_glsl_to_spirv("ui_text_fragment");
} else #if OS == .ANDROID {
    MESH_VERTEX_SHADER      : CompiledShader;
    MESH_FRAGMENT_SHADER    : CompiledShader;
    UI_VERTEX_SHADER        : CompiledShader;
    UI_FRAGMENT_SHADER      : CompiledShader;
    UI_TEXT_FRAGMENT_SHADER : CompiledShader;
}

LoamState :: struct {
    assets : *AssetState;
    vk : *Vk;

    renderCommands : [..] RenderCommand;

    camera : *Camera;
    
    defaultFont : *FontData;
}

init_loam :: (window : Window_Type, initialWidth : float, initialHeight : float) -> *LoamState {
    #if OS == .ANDROID {
	MESH_VERTEX_SHADER      = load_spirv_for_android("mesh_vertex");
	MESH_FRAGMENT_SHADER    = load_spirv_for_android("mesh_fragment");
	UI_VERTEX_SHADER        = load_spirv_for_android("ui_vertex");
	UI_FRAGMENT_SHADER      = load_spirv_for_android("ui_fragment");
	UI_TEXT_FRAGMENT_SHADER = load_spirv_for_android("ui_text_fragment");
    }
    
    loam := New(LoamState);
    #if IS_DEBUG then this_allocation_is_not_a_leak(loam);

    loam.assets = New(AssetState);
    #if IS_DEBUG then this_allocation_is_not_a_leak(loam.assets);
    loam.assets.directory = load_asset_directory();
    loam.assets.cacheSentinel.prev = *loam.assets.cacheSentinel;
    loam.assets.cacheSentinel.next = *loam.assets.cacheSentinel;

    loam.camera = New(Camera);
    #if IS_DEBUG then this_allocation_is_not_a_leak(loam.camera);
    loam.camera.verticalFOV = 80.0;
    loam.camera.dimensions = .{ initialWidth, initialHeight };
    loam.camera.position.z = -2;

    loam.camera.isOrthographic = false;
    
    loam.vk = New(Vk);
    #if IS_DEBUG then this_allocation_is_not_a_leak(loam.vk);
    init_vk(loam, window);

    fontAsset := request_asset(loam, .Font, "internal", true);
    loam.defaultFont = cast(*FontData) fontAsset.data;
    
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

// TODO: We probably want to always make sure this is being called before draw calls start happening, so have a begin and end function which sets\
//       a variable the render commands verify against
reset_info_for_rendering :: (loam : *LoamState) {
    vkDeviceWaitIdle(loam.vk.device);
    dynamic_descriptor_pool_allocator_reset_pools(*loam.vk.descriptorAllocator, loam.vk.device);
    
    cleanup_single_frame_images(loam.vk);
    cleanup_single_frame_buffers(loam.vk);
    
    array_reset(*loam.renderCommands);
}

#load "assets.jai";
#load "camera.jai";
#load "debug.jai";
#load "math.jai";
#load "render_commands.jai";
#load "transform.jai";
#load "utility.jai";
#load "vk/vk.jai";

#import "Basic"() (MEMORY_DEBUGGER = IS_DEBUG && OS == .WINDOWS);
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
#import "Window_Creation";

#if OS == .WINDOWS {
    Windows :: #import "Windows";
    
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
#import "Logger" (IS_DEBUG);
#import "VMA";
#import "Vulkan_1_3";
