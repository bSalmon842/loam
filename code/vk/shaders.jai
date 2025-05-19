/*
Project: Loam
File: shaders.jai
Author: Brock Salmon
Created: 19MAY2025
*/

// NOTE: re: Shader file names: We enforce a shader naming style where the name must end with the type of shader it is
// Currently supported: "...vertex", "...fragment"

FORCE_SHADER_REBUILD :: false;
#if FORCE_SHADER_REBUILD then #run print_color("\tFORCING REBUILD OF ALL SHADERS\n\n", color=.HI_YELLOW);

CompiledShader :: struct {
    name : string;
    code : string;
    succeeded : bool;
}

load_shader_module :: (device : VkDevice, shaderToLoad : CompiledShader) -> VkShaderModule #must {
    if !shaderToLoad.succeeded {
	log(.ERROR, tprint("% was not compiled and cannot be found.", shaderToLoad.name));
	assert(false);
    }

    shaderModule : VkShaderModule;
    shaderCreateInfo := VkShaderModuleCreateInfo.{ codeSize = cast(u64) shaderToLoad.code.count, pCode = cast(*u32) shaderToLoad.code.data };
    check_vk(vkCreateShaderModule(device, *shaderCreateInfo, null, *shaderModule), tprint("Failed to create shader: %", shaderToLoad.name));
    return shaderModule;
}

shader_file_already_compiled :: (hlslName : string) -> bool #must {
    lastFile := tprint("%1%2.hlsl", LAST_COMPILED_HLSL_FOLDER_PATH, hlslName);
    inFile := tprint("%1%2.hlsl", SHADER_FOLDER_PATH, hlslName);

    lastContents, foundLastFile := read_entire_file(lastFile, log_errors=false);
    if !foundLastFile then return false;

    inContents, foundInFile := read_entire_file(inFile, log_errors=false);
    if !foundInFile {
	print_color("%\n", tprint("\tShader \"%\" does not exist.", hlslName), color=.HI_RED);
	return false;
    }
    
    return compare(lastContents, inContents) == 0;
}

compile_hlsl_to_spirv :: (hlslName : string) -> CompiledShader #must {
    if !#compile_time then assert(false, tprint("% can only be called at compile time (%)\n", #this, hlslName));

    make_directory_if_it_does_not_exist(COMPILED_SHADER_FOLDER_PATH);
    make_directory_if_it_does_not_exist(LAST_COMPILED_HLSL_FOLDER_PATH);

    inFile := tprint("%1%2.hlsl", SHADER_FOLDER_PATH, hlslName);
    outFile := tprint("%1%2.spv", COMPILED_SHADER_FOLDER_PATH, hlslName);
    lastFile := tprint("%1%2.hlsl", LAST_COMPILED_HLSL_FOLDER_PATH, hlslName);
    alreadyCompiled := shader_file_already_compiled(hlslName) && !FORCE_SHADER_REBUILD;

    if !alreadyCompiled {
	if file_exists(outFile) then file_delete(outFile);
	if ends_with(hlslName, "vertex") {
	    run_command(DXC_PATH, "-spirv", "-T", "vs_6_4", "-E", "main", inFile, "-Fo", outFile);
	} else if ends_with(hlslName, "fragment") {
	    run_command(DXC_PATH, "-spirv", "-T", "ps_6_4", "-E", "main", inFile, "-Fo", outFile);
	} else {
	    assert(false, "Invalid shader name, does not include shader type");
	}
    }

    spvContents, foundFile := read_entire_file(outFile);
    if foundFile && !alreadyCompiled {
	print_color("%\n", tprint("\tShader \"%\" was successfully compiled.", hlslName), color=.HI_GREEN);
	copy_file(inFile, lastFile);
    } else if foundFile && alreadyCompiled {
	print_color("%\n", tprint("\tShader \"%\" unchanged, skipping.", hlslName), color=.HI_CYAN);
    } else {
	print_color("%\n", tprint("\tShader \"%\" failed to compile.", hlslName), color=.HI_RED);
    }

    return CompiledShader.{ hlslName, spvContents, foundFile };
}

#if OS == .ANDROID {
    SHADER_FOLDER_PATH             :: "/shaders";
    load_spirv_for_android :: (hlslName : string) -> CompiledShader #must {
	spvContents, foundFile := read_entire_file(tprint("%1%2/%.spv", to_string(context.android_app.activity.externalDataPath), SHADER_FOLDER_PATH, hlslName));
	return CompiledShader.{ hlslName, spvContents, foundFile };
    }
} else {
    SHADER_FOLDER_PATH             :: "shaders/";
    COMPILED_SHADER_FOLDER_PATH    :: "shaders/compiled/";
    LAST_COMPILED_HLSL_FOLDER_PATH :: "shaders/last_files/";
    DXC_PATH                       :: "C:/work/spirv/dxc/bin/x64/dxc.exe";
}
