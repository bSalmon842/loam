/*
Project: Loam
File: vk/shaders.jai
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

load_shader_module :: (device : VkDevice, shaderToLoad : CompiledShader) -> VkShaderModule {
    if !shaderToLoad.succeeded {
	log(.ERROR, tprint("% was not compiled and cannot be found.", shaderToLoad.name));
	assert(false);
    }

    shaderModule : VkShaderModule;
    shaderCreateInfo := VkShaderModuleCreateInfo.{ codeSize = cast(u64) shaderToLoad.code.count, pCode = cast(*u32) shaderToLoad.code.data };
    check_vk(vkCreateShaderModule(device, *shaderCreateInfo, null, *shaderModule), tprint("Failed to create shader: %", shaderToLoad.name));
    return shaderModule;
}

shader_file_already_compiled :: (glslName : string) -> bool {
    lastFile := tprint("%1%2.glsl", LAST_COMPILED_GLSL_FOLDER_PATH, glslName);
    inFile := tprint("%1%2.glsl", SHADER_FOLDER_PATH, glslName);

    lastContents, foundLastFile := read_entire_file(lastFile, log_errors=false);
    if !foundLastFile then return false;

    inContents, foundInFile := read_entire_file(inFile, log_errors=false);
    if !foundInFile {
	print_color("%\n", tprint("\tShader \"%\" does not exist.", glslName), color=.HI_RED);
	return false;
    }
    
    return compare(lastContents, inContents) == 0;
}

compile_glsl_to_spirv :: (glslName : string) -> CompiledShader {
    if !#compile_time then assert(false, tprint("% can only be called at compile time (%)\n", #this, glslName));

    make_directory_if_it_does_not_exist(COMPILED_SHADER_FOLDER_PATH);
    make_directory_if_it_does_not_exist(LAST_COMPILED_GLSL_FOLDER_PATH);

    inFile := tprint("%1%2.glsl", SHADER_FOLDER_PATH, glslName);
    outFile := tprint("%1%2.spv", COMPILED_SHADER_FOLDER_PATH, glslName);
    lastFile := tprint("%1%2.glsl", LAST_COMPILED_GLSL_FOLDER_PATH, glslName);
    alreadyCompiled := shader_file_already_compiled(glslName) && !FORCE_SHADER_REBUILD;

    if !alreadyCompiled {
	if file_exists(outFile) then file_delete(outFile);
	if ends_with(glslName, "vertex") {
	    run_command(GLSLC_PATH, "-fshader-stage=vertex", inFile, tprint("-o%", outFile));
	} else if ends_with(glslName, "fragment") {
	    run_command(GLSLC_PATH, "-fshader-stage=fragment", inFile, tprint("-o%", outFile));
	} else {
	    assert(false, "Invalid shader name, does not include shader type");
	}
    }

    spvContents, foundFile := read_entire_file(outFile);
    if foundFile && !alreadyCompiled {
	print_color("%\n", tprint("\tShader \"%\" was successfully compiled.", outFile), color=.HI_GREEN);
	copy_file(inFile, lastFile);
    } else if foundFile && alreadyCompiled {
	print_color("%\n", tprint("\tShader \"%\" unchanged, skipping.", inFile), color=.HI_CYAN);
    } else {
	print_color("%\n", tprint("\tShader \"%\" failed to compile.", inFile), color=.HI_RED);
    }

    return CompiledShader.{ glslName, spvContents, foundFile };
}

#if OS == .ANDROID {
    load_spirv_for_android :: (hlslName : string) -> CompiledShader {
	spvContents, foundFile := read_entire_file(context.android_app.activity.assetManager, tprint("%1%2.spv", SHADER_FOLDER_PATH, hlslName));
	return CompiledShader.{ hlslName, spvContents, foundFile };
    }
    SHADER_FOLDER_PATH             :: "shaders/";
} else {
    COMPILED_SHADER_FOLDER_PATH    :: "C:/work/bs_modules/loam/code/shaders/compiled/";
    LAST_COMPILED_GLSL_FOLDER_PATH :: "C:/work/bs_modules/loam/code/shaders/last_files/";
    GLSLC_PATH                     :: "C:/work/spirv/glslc/bin/glslc.exe";
    SHADER_FOLDER_PATH             :: "C:/work/bs_modules/loam/code/shaders/";
}
