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

main :: () {
    #if OS == .WINDOWS {
        Windows.SetProcessDPIAware();
        Windows.timeBeginPeriod(1);
    }

    make_log_file("loam", .YEAR | .MONTH | .DAY | .HOUR);
    
    window := create_window(windowWidth, windowHeight, "loam");

    vk := New(Vk);
    check_vk(create_vk_instance(vk, "Test App"), "create_vk_instance failed: ");
    check_vk(create_vk_surface(vk, window), "create_vk_surface failed: ");
    check_vk(get_vk_physical_device(vk), "get_vk_physical_device failed: ");
    check_vk(create_vk_device(vk), "create_vk_devices failed: ");

    vk.graphicsCmdPool = create_command_pool(vk.device, vk.queueFamilyIndices.graphics);
    vkGetDeviceQueue(vk.device, vk.queueFamilyIndices.graphics, 0, *vk.graphicsQueue);

    check_vk(create_vk_swapchain(vk), "create_vk_swapchain failed: ");
    
    deltaTime = seconds_since_init();
    lastTime := seconds_since_init();
    while running := true {
        update_window_events();
        
        for get_window_resizes() {
            windowWidth, windowHeight = Simp.get_render_dimensions(it.window);
        }
        
        for events_this_frame {
            if it.type == {
                case .QUIT; break running;
            }
        }
        
        deltaTime = seconds_since_init() - lastTime;
        lastTime = seconds_since_init();
        
        reset_temporary_storage();
    }
}

#load "utility.jai";

#load "vk/init.jai";
#load "vk/util.jai";

#import "Basic";
#import "Input";
#import "Math";
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
}

// BS_Modules
//cgltf :: #import "cgltf";
//ImGui :: #import "ImGui_1_9";
#import "Logger" (IS_DEBUG);
#import "Vulkan_1_3";
