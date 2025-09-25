/*
Project: Loam Asset Packer
File: build.jai
Author: Brock Salmon
Created: 25SEP2025
*/

Build_Release :: false;

#run {
    buildFolderPath := "../../build/";
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
    targetOptions.output_executable_name = tprint(ifx Build_Release then "%" else "debug_%", "loam_assetpacker");
    targetOptions.output_path = buildFolderPath;
    targetOptions.os_target = .WINDOWS;
    
    add_generic_build_options(*targetOptions, false);
    set_optimization(*targetOptions, ifx Build_Release then .VERY_OPTIMIZED else .VERY_DEBUG);
    set_build_options(targetOptions, workspace);
    add_build_file("asset_packer.jai", workspace);
    
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

#import "Basic";
#import "Compiler";
#import "File";
#import "File_Utilities";
#import "Math";
#import "Metaprogram_Plugins";
#import "Process";
#import "String";
#import "Toolchains/Android";

