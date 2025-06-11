/*
Project: Loam
File: engine.jai
Author: Brock Salmon
Created: 08JUN2025
*/

LoamState :: struct {
    assets : *AssetState;
    vk : *Vk;
}

init_loam :: (window : Window_Type) -> *LoamState {
    loam := New(LoamState);

    loam.assets = New(AssetState);
    loam.assets.directory = load_asset_directory();
    loam.assets.cacheSentinel.prev = *loam.assets.cacheSentinel;
    loam.assets.cacheSentinel.next = *loam.assets.cacheSentinel;

    loam.vk = New(Vk);
    init_vk(loam, window);
    
    return loam;
}

#load "assets.jai";
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
