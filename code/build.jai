/*
File: build.jai
Author: Brock Salmon
Created: 24MAR2025
*/

#import "Basic";
#import "Compiler";
#import "File";
#import "File_Utilities";
#import "Math";
#import "Metaprogram_Plugins";
#import "Process";
#import "String";
#import "Toolchains/Android";

MAIN_FILE :: "main.jai";
APP_NAME :: "loam";

Build_Release :: false;

Build_Windows       :: true;
Build_Linux         :: false;
Build_Android_ARM64 :: true;

#run build_main();
#if OS == .WINDOWS && Build_Windows {
    #run build_asset_packer();
}

build_main :: () {
    os_targets, cpu_targets := get_os_targets();
    if os_targets.count == 0 {
        assert(false, "No Compile Targets defined.");
    }
    
    buildFolderPath := "../build/";
    make_directory_if_it_does_not_exist(buildFolderPath);
    for target_os : os_targets {
        target_cpu := cpu_targets[it_index];
        
        buildFolderPath = "../build/";
        osString := enum_names(Operating_System_Tag)[target_os];
        if target_os == .ANDROID then osString = tprint("%", osString);
        osString = to_lower_copy(osString);
        buildFolderPath = join(buildFolderPath, osString, "/");
        make_directory_if_it_does_not_exist(buildFolderPath);
        
        buildModeString := ifx Build_Release then "release" else "debug";
        buildFolderPath = join(buildFolderPath, buildModeString);
        make_directory_if_it_does_not_exist(buildFolderPath);
        
        workspaceName := tprint("%_%", osString, buildModeString);
        workspace := compiler_create_workspace(workspaceName);
        if !workspace {
            compiler_report(tprint("Failed to create workspace: %", workspaceName));
            return;
        }
        
        dt := to_calendar(current_time_consensus(), .LOCAL);
        dtString := tprint("(%/%/% %:%:%)", dt.year, formatInt(dt.month_starting_at_0 + 1, minimum_digits=2), formatInt(dt.day_of_month_starting_at_0 + 1, minimum_digits=2), formatInt(dt.hour, minimum_digits=2), formatInt(dt.minute, minimum_digits=2), formatInt(dt.second, minimum_digits=2));
        print("Compiling % @ %\n", workspaceName, dtString);
        
        targetOptions := get_build_options(workspace);
        targetOptions.output_executable_name = tprint(ifx Build_Release then "%" else "debug_%", APP_NAME);
        targetOptions.output_path = buildFolderPath;
        targetOptions.os_target = target_os;
	targetOptions.text_output_flags = .OUTPUT_TIMING_INFO;
            
        androidDirectory : string = "";
        androidBuildOutputDirectory : string = "";
        sdkLibPath : string = "";
        if target_os == .ANDROID {
            targetTriple, targetTripleWithSDK := get_android_target_triple(target_cpu);
            ndkPaths := get_ndk_paths();
            sdkLibPath = tprint("%/usr/lib/%", ndkPaths.sysroot, targetTriple);
            
            config : Android_Project_Config;
            config.app_name = targetOptions.output_executable_name;
            config.app_id = tprint("com.az.%", config.app_name);
            config.screen_orientation = .LANDSCAPE;
            config.lib_name = targetOptions.output_executable_name;
            config.project_path = tprint("%", buildFolderPath);
            if !generate_android_project(*config) {
                compiler_report(tprint("Failed to create android project \"%\"", config.project_path));
                return;
            }
            
            // Compute & create the library directory
            androidDirectory = tprint("%/app/src/main", config.project_path);
            androidBuildOutputDirectory = tprint("%/jniLibs/%", androidDirectory, get_android_project_jni_architecture_name(target_cpu));
            make_directory_if_it_does_not_exist(androidBuildOutputDirectory, recursive = true);
            
            if target_cpu == .ARM64 {
                targetOptions.backend = .LLVM;
                targetOptions.llvm_options.target_system_features = "+lse";
            }
            targetOptions.cpu_target = target_cpu;
            targetOptions.llvm_options.target_system_triple = targetTripleWithSDK;
            targetOptions.output_type = .DYNAMIC_LIBRARY;
            targetOptions.use_custom_link_command = true;
            targetOptions.output_path = androidBuildOutputDirectory;
        }
        add_generic_build_options(*targetOptions, true);
        set_optimization(*targetOptions, ifx Build_Release then .VERY_OPTIMIZED else .VERY_DEBUG);
        set_build_options(targetOptions, workspace);
        
        if target_os == .WINDOWS {
            set_build_options_dc(.{do_output=false, append_linker_arguments=.["/SUBSYSTEM:windows", "/ENTRY:mainCRTStartup"]});
        }
        
        compiler_begin_intercept(workspace);
        add_build_file(tprint("%/%", #filepath, MAIN_FILE), workspace);
        
        while true {
            message := compiler_wait_for_message();
            if message.kind == {
                case .PHASE; {
                    phaseMessage := cast(*Message_Phase) message;
                    if phaseMessage.phase == .READY_FOR_CUSTOM_LINK_COMMAND {
                        run_android_link_command(phaseMessage, targetOptions, extra_args = .[tprint("-L%", sdkLibPath), "-lc++"]);
                    }
                }
                
                case .ERROR; exit(1);
                case .COMPLETE; break;
            }
        }
        compiler_end_intercept(workspace);
        
        if target_os == .ANDROID {
            resourcesOutputDirectory := tprint("%/assets", androidDirectory);
            make_directory_if_it_does_not_exist(resourcesOutputDirectory, recursive = true);
            copy_directory("../data", tprint("%/data", resourcesOutputDirectory));
	    copy_directory("../code/shaders/compiled", tprint("%/shaders", resourcesOutputDirectory));
    
            success := copy_android_libcpp(target_cpu, targetOptions.output_path);
            if !success {
                compiler_report(tprint("Could not copy Android libc++ to %", targetOptions.output_path));
            }
        }
    }
}

build_asset_packer :: () {    
    buildFolderPath := "../build/";
    make_directory_if_it_does_not_exist(buildFolderPath);

    osString := enum_names(Operating_System_Tag)[Operating_System_Tag.WINDOWS];
    osString = to_lower_copy(osString);
    buildFolderPath = join(buildFolderPath, osString, "/");
    make_directory_if_it_does_not_exist(buildFolderPath);
    
    buildModeString := ifx Build_Release then "release" else "debug";
    buildFolderPath = join(buildFolderPath, buildModeString);
    make_directory_if_it_does_not_exist(buildFolderPath);

    buildFolderPath = join(buildFolderPath, "/asset_packer/");
    make_directory_if_it_does_not_exist(buildFolderPath);
    
    workspaceName := tprint("%_assetpacker_%", osString, buildModeString);
    workspace := compiler_create_workspace(workspaceName);
    if !workspace {
        compiler_report(tprint("Failed to create workspace: %", workspaceName));
        return;
    }
    
    dt := to_calendar(current_time_consensus(), .LOCAL);
    dtString := tprint("(%/%/% %:%:%)", dt.year, formatInt(dt.month_starting_at_0 + 1, minimum_digits=2), formatInt(dt.day_of_month_starting_at_0 + 1, minimum_digits=2), formatInt(dt.hour, minimum_digits=2), formatInt(dt.minute, minimum_digits=2), formatInt(dt.second, minimum_digits=2));
    print("Compiling % @ %\n", workspaceName, dtString);
    
    targetOptions := get_build_options(workspace);
    targetOptions.output_executable_name = tprint(ifx Build_Release then "%" else "debug_%", tprint("%_%", APP_NAME, "assetpacker"));
    targetOptions.output_path = buildFolderPath;
    targetOptions.os_target = .WINDOWS;
    
    add_generic_build_options(*targetOptions, false);
    set_optimization(*targetOptions, ifx Build_Release then .VERY_OPTIMIZED else .VERY_DEBUG);
    set_build_options(targetOptions, workspace);
    add_build_file(tprint("%/%", #filepath, "asset_packer/asset_packer.jai"), workspace);
    
    set_build_options_dc(.{do_output=false, append_linker_arguments=.["/SUBSYSTEM:windows", "/ENTRY:mainCRTStartup"]});
}

add_generic_build_options :: (options : *Build_Options, timing : bool) {
    options.text_output_flags = 2;
    options.dead_code_elimination = .ALL;
    options.use_visual_studio_message_format = false;
    options.additional_linker_arguments = .[ "/NOIMPLIB", "/NOEXP" ];
    options.text_output_flags = ifx timing then .OUTPUT_TIMING_INFO else cast(type_of(Build_Options.text_output_flags)) 0;
    
    modulesPaths : [..] string;
    array_add(*modulesPaths, ..options.import_path);
    #if OS == .WINDOWS {
	array_add(*modulesPaths, "C:/work/bs_modules");
    } else {
	array_add(*modulesPaths, "~/work/bs_modules");
    }
    options.import_path = modulesPaths;
}

get_os_targets :: () -> [..] Operating_System_Tag, [..] CPU_Tag {
    arr_os : [..] Operating_System_Tag;
    arr_cpu : [..] CPU_Tag;
    if Build_Windows {
        array_add(*arr_os, .WINDOWS);
        array_add(*arr_cpu, .UNINITIALIZED);
    }
    if Build_Linux {
	array_add(*arr_os, .LINUX);
	array_add(*arr_cpu, .X64);
    }
    if Build_Android_ARM64 {
        array_add(*arr_os, .ANDROID);
        array_add(*arr_cpu, .ARM64);
    }
    
    return arr_os, arr_cpu;
}

is_target :: (os : Operating_System_Tag, targets : [] Operating_System_Tag) -> bool {
    for targets {
        if it == os then return true;
    }
    
    return false;
}
