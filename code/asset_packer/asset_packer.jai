/*
Project: Loam
File: asset_packer.jai
Author: Brock Salmon
Created: 24MAY2025
*/

windowWidth  := 1280;
windowHeight := 720;
deltaTime : float64;

// NOTE: We set this for get_packaged_assets_path as we will always be packaging into the dev data folders
IS_DEV :: true;

// Font Info
TEST_STRING :: "Sphinx of Black Quartz, judge my vow\0";
FONT_SMALL  : *ImGui.ImFont;
FONT_MEDIUM : *ImGui.ImFont;
FONT_BIG    : *ImGui.ImFont;

PROJECT_FILE_EXTENSION :: "lapp";

ALLOW_CORE_BUILDING :: true;

CURRENT_AUDIO : Sound_Data;
CURRENT_STREAM : *Sound_Stream;
playCursor : float;

ProjectEntry :: struct {
    name : string;
    type : AssetType;
    size : u64;
    filepath : string;
    
    union {
	audio : PackerInfo_Audio;
	image : PackerInfo_Image;
    }
}

PackerProject :: struct {
    name : string;
    exportDirectory : string;
    entries : [..] ProjectEntry;
}

PackerInfo_Audio :: struct {
    duration   : float;
    channels   : u32;
    sampleRate : u32;
}

PackerInfo_Image :: struct {
    width : u32;
    height : u32;
    mipLevels : u32;
}

PackerState :: struct {
    project : *PackerProject;
    
    entryToAdd : ProjectEntry;
    selectedEntryIndex : s64 = -1;
    
    glTexture : u32;

    fontToAdd  : string;
    loadedFont : string;

    jsonToAdd  : string;
    loadedJSON : string;

    audioIsPlaying : bool;
}

load_project_file :: (path : string, project : *PackerProject) -> bool {
    fileContents, readSuccess := read_entire_file(path);
    if readSuccess {
	root, err := json_build_tree(fileContents, "asset_packer project");
	free(fileContents.data);
	if err then return false;

	{
	    projectName, found := json_get_from_object(root, "project_name", string);
	    if !found then return false;
	    project.name = copy_string(projectName);
	}

	{
	    // NOTE: We're okay with skipping this if it's not found in the project file
	    dirName, found := json_get_from_object(root, "export_directory", string);
	    if found then project.exportDirectory = copy_string(dirName);
	}
	
	for root.values {
	    if it.type == .Object {
		entry : ProjectEntry;
		entry.name = copy_string(it.name);

		{
		    typeString, found := json_get_from_object(it, "type", string);
		    if !found then return false;
		    entry.type, found = enum_name_to_value(AssetType, typeString);
		    if !found then return false;
		}
		
		{
		    size, found := json_get_from_object(it, "size", float64);
		    if !found then return false;
		    entry.size = round_to(size, u64);
		}
		
		{
		    filepathString, found := json_get_from_object(it, "filepath", string);
		    if !found then return false;
		    entry.filepath = copy_string(filepathString);
		}

		if entry.type == .Image {
		    {
			width, found := json_get_from_object(it, "width", float64);
			if !found then return false;
			entry.image.width = round_to(width, u32);
		    }

		    {
			height, found := json_get_from_object(it, "height", float64);
			if !found then return false;
			entry.image.height = round_to(height, u32);
		    }

		    {
			mipLevels, found := json_get_from_object(it, "mipLevels", float64);
			if !found then return false;
			entry.image.mipLevels = round_to(mipLevels, u32);
		    }
		} else if entry.type == .Audio {
		    {
			duration, found := json_get_from_object(it, "duration", float64);
			if !found then return false;
			entry.audio.duration = cast(float) duration;
		    }
		    
		    {
			channels, found := json_get_from_object(it, "channels", float64);
			if !found then return false;
			entry.audio.channels = round_to(channels, u32);
		    }
		    
		    {
			sampleRate, found := json_get_from_object(it, "sampleRate", float64);
			if !found then return false;
			entry.audio.sampleRate = round_to(sampleRate, u32);
		    }
		}
		
		array_add(*project.entries, entry);
	    }
	}
	json_free_value(root);
	return true;
    }

    return false;
}

save_project_file :: (path : string, project : *PackerProject) -> bool {
    root := New(JSON_Value);
    root.type = .Object;
    root.name = copy_string("root");

    projName := New(JSON_Value);
    projName.type = .String;
    projName.name = copy_string("project_name");
    projName.parent = root;
    projName.value_string = copy_string(project.name);
    array_add(*root.values, projName);

    exportDirName := New(JSON_Value);
    exportDirName.type = .String;
    exportDirName.name = copy_string("export_directory");
    exportDirName.parent = root;
    exportDirName.value_string = copy_string(project.exportDirectory);
    array_add(*root.values, exportDirName);

    for project.entries {
	entry := New(JSON_Value);
	entry.type = .Object;
	entry.name = copy_string(it.name);
	entry.parent = root;
	array_add(*root.values, entry);

	{
	    value := New(JSON_Value);
	    value.type = .String;
	    value.name = copy_string("type");
	    value.parent = entry;

	    value.value_string = copy_string(enum_value_to_name(it.type));
	    array_add(*entry.values, value);
	}

	{
	    value := New(JSON_Value);
	    value.type = .Number;
	    value.name = copy_string("size");
	    value.parent = entry;

	    value.value_float = cast(float64) it.size;
	    array_add(*entry.values, value);
	}

	{
	    value := New(JSON_Value);
	    value.type = .String;
	    value.name = copy_string("filepath");
	    value.parent = entry;
	    
	    value.value_string = copy_string(it.filepath);
	    array_add(*entry.values, value);
	}

	if it.type == .Image {
	    {
		value := New(JSON_Value);
		value.type = .Number;
		value.name = copy_string("width");
		value.parent = entry;

		value.value_float = cast(float64) it.image.width;
		array_add(*entry.values, value);
	    }

	    {
		value := New(JSON_Value);
		value.type = .Number;
		value.name = copy_string("height");
		value.parent = entry;

		value.value_float = cast(float64) it.image.height;
		array_add(*entry.values, value);
	    }

	    {
		value := New(JSON_Value);
		value.type = .Number;
		value.name = copy_string("mipLevels");
		value.parent = entry;

		value.value_float = cast(float64) it.image.mipLevels;
		array_add(*entry.values, value);
	    }
	} else if it.type == .Audio {
	    {
		value := New(JSON_Value);
		value.type = .Number;
		value.name = copy_string("duration");
		value.parent = entry;

		value.value_float = cast(float64) it.audio.duration;
		array_add(*entry.values, value);
	    }

	    {
		value := New(JSON_Value);
		value.type = .Number;
		value.name = copy_string("channels");
		value.parent = entry;

		value.value_float = cast(float64) it.audio.channels;
		array_add(*entry.values, value);
	    }

	    {
		value := New(JSON_Value);
		value.type = .Number;
		value.name = copy_string("sampleRate");
		value.parent = entry;

		value.value_float = cast(float64) it.audio.sampleRate;
		array_add(*entry.values, value);
	    }
	}
    }

    if !json_write_file(path, root) {
	return false;
    }

    json_free_value(root);
    return true;
}

main :: () {
    Windows.SetProcessDPIAware();
    Windows.timeBeginPeriod(1);

    make_log_file("loam_assetpacker", .YEAR | .MONTH | .DAY | .HOUR | .MINUTE);

    window := create_window(windowWidth, windowHeight, "loam_assetpacker");

    Windows.DragAcceptFiles(window, cast(Windows.BOOL) true);
    Simp.set_render_target(window);

    devices := get_devices();
    sound_player_init(.{});
    
    ImGui.CreateContext();
    ImGui.ImplJai_Init(window);
    ImGui.ImplOpenGL3_Init();
    
    packer := New(PackerState);
    packer.project = New(PackerProject);
    
    startArgs := get_command_line_arguments();
    for startArgs {
	if path_extension(it) == PROJECT_FILE_EXTENSION {
	    if !load_project_file(it, packer.project) {
		log(.ERROR, tprint("Failed to load project file: %", it));
	    }
	}
    }
    
    deltaTime = seconds_since_init();
    lastTime := seconds_since_init();
    while running := true {
        update_window_events();
        
        for get_window_resizes() {
	    Simp.update_window(it.window);
            windowWidth, windowHeight = Simp.get_render_dimensions(it.window);
        }
	
        for events_this_frame {
            if it.type == {
                case .QUIT; break running;

		case .DRAG_AND_DROP_FILES; {
		    for it.files {
			packer.entryToAdd.filepath = copy_string(it);
			path_overwrite_separators(packer.entryToAdd.filepath, #char "/");
			detect_asset_type(packer);
			process_asset_from_file(packer);
			
			nameTaken := false;
			for packer.project.entries {
			    if it.name == packer.entryToAdd.name {
				nameTaken = true;
				break;
			    }
			}

			if !nameTaken {
			    array_add(*packer.project.entries, packer.entryToAdd);
			}
			
			packer.entryToAdd = .{};
		    }
		}
	    }
        }
	
	if packer.fontToAdd.count {
	    ImGui.CreateContext();
    	    io := ImGui.GetIO();
	    ImGui.ImFontAtlas.Clear(io.Fonts);
	    ImGui.ImFontAtlas.AddFontDefault(io.Fonts);
	    
	    FONT_SMALL  = ImGui.ImFontAtlas.AddFontFromFileTTF(io.Fonts, packer.fontToAdd.data, 16.0, null, ImGui.ImFontAtlas.GetGlyphRangesDefault(io.Fonts));
	    FONT_MEDIUM = ImGui.ImFontAtlas.AddFontFromFileTTF(io.Fonts, packer.fontToAdd.data, 32.0, null, ImGui.ImFontAtlas.GetGlyphRangesDefault(io.Fonts));
	    FONT_BIG    = ImGui.ImFontAtlas.AddFontFromFileTTF(io.Fonts, packer.fontToAdd.data, 64.0, null, ImGui.ImFontAtlas.GetGlyphRangesDefault(io.Fonts));
	    packer.loadedFont = packer.fontToAdd;
	    packer.fontToAdd = "";

    	    ImGui.ImFontAtlas.Build(io.Fonts);

	    ImGui.ImplOpenGL3_DestroyDeviceObjects();
	    ImGui.ImplOpenGL3_CreateDeviceObjects();
	}

	if packer.jsonToAdd.count {
	    if packer.loadedJSON.count {
		free(packer.loadedJSON.data);
	    }
	    fileContents, success := read_entire_file(packer.jsonToAdd);
	    packer.loadedJSON = fileContents;
	    assert(success, "Failed to load JSON file");
	    packer.jsonToAdd = "";
	}
	
	ImGui.ImplOpenGL3_NewFrame();
	ImGui.ImplJai_NewFrame();
	ImGui.NewFrame();
	
	Simp.clear_render_target(0.1, 0.1, 0.1, 1);
	
	ImGui.SetNextWindowPos(.{});
	ImGui.SetNextWindowSize(ImGui.ImVec2.{ xx windowWidth, xx windowHeight });
	ImGui.Begin("Main Window", flags = .NoTitleBar | .NoResize | .NoMove | .MenuBar | .NoScrollbar | .NoScrollWithMouse);

	ImGui.BeginMenuBar();
	if ImGui.BeginMenu("Project") {
	    if ImGui.MenuItem("Save") {
		#if OS == .WINDOWS {
		    buffer : [256] u8;
		    
		    ofn : Windows.OPENFILENAMEA;
		    ofn.lStructSize = size_of(Windows.OPENFILENAMEA);
		    ofn.hwndOwner   = window;
		    ofn.lpstrFilter = tprint("Loam Asset Packer File (*.%1)\0*.%1\0\0", PROJECT_FILE_EXTENSION).data;
		    ofn.lpstrFile   = buffer.data;
		    ofn.nMaxFile    = buffer.count;
		    ofn.lpstrTitle  = "Save Project File";
		    ofn.Flags       = Windows.OFN_NOCHANGEDIR;
		    
		    if Windows.GetSaveFileNameA(*ofn) {
			bufferString := trim_right(cast(string) buffer, "\0");
			if !ends_with(bufferString, tprint(".%", PROJECT_FILE_EXTENSION)) {
			    bufferString = tprint("%.%", bufferString, PROJECT_FILE_EXTENSION);
			}
			if !save_project_file(bufferString, packer.project) {
			    log(.ERROR, tprint("Failed to save project file: %", cast(string) buffer));
			}
		    }
		}
	    }
	    if ImGui.MenuItem("Load") {
		free(packer.project.name.data);
		packer.project.name = .{};
		for * packer.project.entries {
		    free(it.name.data);
		    it.name = .{};
		    
		    free(it.filepath.data);
		    it.filepath = .{};
		}
		array_reset(*packer.project.entries);

                #if OS == .WINDOWS {
		    buffer : [256] u8;
		    
		    ofn : Windows.OPENFILENAMEA;
		    ofn.lStructSize = size_of(Windows.OPENFILENAMEA);
		    ofn.hwndOwner   = window;
		    ofn.lpstrFilter = tprint("Loam Asset Packer File (*.%1)\0*.%1\0\0", PROJECT_FILE_EXTENSION).data;
		    ofn.lpstrFile   = buffer.data;
		    ofn.nMaxFile    = buffer.count;
		    ofn.lpstrTitle  = "Open Project File";
		    ofn.Flags       = Windows.OFN_NOCHANGEDIR;
		    
		    if Windows.GetOpenFileNameA(*ofn) {
			if !load_project_file(cast(string) buffer, packer.project) {
			    log(.ERROR, tprint("Failed to load project file: %", cast(string) buffer));
			}
		    }
		}

	    }
	    ImGui.EndMenu();
	}
	ImGui.EndMenuBar();
	
	// Asset Table
	ImGui.SetNextWindowPos(.{ 5, 25 });
	listWindowSize := ImGui.ImVec2.{ windowWidth * 0.6 - 10.0, windowHeight - 95.0 };
	ImGui.BeginChild("Asset List Window", listWindowSize, .Border, .NoTitleBar | .NoResize | .NoMove);
	ImGui.BeginTable("Asset List", 4, flags = .RowBg | .Borders);
	ImGui.TableSetupColumn("Name", .WidthFixed, 150.0);
	ImGui.TableSetupColumn("Type", .WidthFixed, 50.0);
	ImGui.TableSetupColumn("Size", .WidthFixed, 60.0);
	ImGui.TableSetupColumn("Filepath");

	ImGui.TableNextRow(.Headers);
	ImGui.TableNextColumn();
	ImGui.Text("Name");
	ImGui.TableNextColumn();
	ImGui.Text("Type");
	ImGui.TableNextColumn();
	ImGui.Text("Size");
	ImGui.TableNextColumn();
	ImGui.Text("Filepath");

	for * packer.project.entries {
	    isFileMissing := !file_exists(it.filepath);
	    if isFileMissing then ImGui.PushStyleColor(ImGui.Col.Text, .{ 1, 0, 0, 1 });
	    ImGui.TableNextRow();
	    ImGui.TableNextColumn();
	    ImGui.Text(cast(string) it.name);
	    ImGui.TableNextColumn();
	    ImGui.Text("%", it.type);
	    ImGui.TableNextColumn();
	    ImGui.Text(to_size_string(it.size));
	    ImGui.TableNextColumn();
	    ImGui.Text(it.filepath);
	    if isFileMissing then ImGui.PopStyleColor();

	    ImGui.SameLine();
	    if ImGui.Selectable(tprint("##row%_selectable\0", it_index).data, flags = .SpanAllColumns | .AllowItemOverlap) {
		packer.selectedEntryIndex = it_index;
		if it.type == {
		    case .Image; {
			GL.glGenTextures(1, *packer.glTexture);
			GL.glBindTexture(GL.GL_TEXTURE_2D, packer.glTexture);
			GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MIN_FILTER, GL.GL_LINEAR);
			GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MAG_FILTER, GL.GL_LINEAR);
			GL.glPixelStorei(GL.GL_UNPACK_ROW_LENGTH, 0);
			
			pngFilepath := join(path_strip_extension(it.filepath), ".png");
			imageWidth, imageHeight, channels : s32;
			imageData := stbi_load(to_c_string(pngFilepath), *imageWidth, *imageHeight, *channels, 4);
			GL.glTexImage2D(GL.GL_TEXTURE_2D, 0, GL.GL_RGBA, xx imageWidth, xx imageHeight, 0, GL.GL_RGBA, GL.GL_UNSIGNED_BYTE, imageData);
			stbi_image_free(imageData);
		    }
		}
	    }
	}
	
	ImGui.EndTable();
	ImGui.EndChild();

	ImGui.SetNextWindowPos(.{ windowWidth * 0.6 + 5.0, 25 });
	windowSize := ImGui.ImVec2.{ (windowWidth * 0.6) - 10.0, windowHeight - 95.0 };
	ImGui.BeginChild("Asset Inspector", windowSize, .Border, .NoTitleBar | .NoResize | .NoMove | .HorizontalScrollbar);
	if packer.selectedEntryIndex != -1 {
	    entry := *packer.project.entries[packer.selectedEntryIndex];
	    if entry.type == {
		case .Image; {
		    image := entry.image;
		    
		    scaledImageWidth : float = xx image.width;
		    scaledImageHeight : float = xx image.height;
		    imageMaxDim := min(windowSize.x - 10, windowSize.y * 0.75);
		    if scaledImageWidth > imageMaxDim || scaledImageHeight > imageMaxDim {
			fitScaleX := imageMaxDim / image.width;
			fitScaleY := imageMaxDim / image.height;
			if fitScaleX < fitScaleY {
			    scaledImageWidth *= fitScaleX;
			    scaledImageHeight *= fitScaleX;
			} else {
			    scaledImageWidth *= fitScaleY;
			    scaledImageHeight *= fitScaleY;
			}
		    }
		    
		    ImGui.Image(cast(*void) (cast(s64) packer.glTexture), ImGui.ImVec2.{ xx scaledImageWidth, xx scaledImageHeight });
		    ImGui.Text("Name: %", cast(string) entry.name);
		    ImGui.Text("Width: %", image.width);
		    ImGui.SameLine();
		    ImGui.Text("\tHeight: %", image.height);
		    ImGui.Text("Mip Levels: %", image.mipLevels);
		}

		case .JSON; {
		    if packer.loadedJSON.count {
			ImGui.Text(packer.loadedJSON);
		    } else {
			packer.jsonToAdd = entry.filepath;
		    }
		}
		
		case .Font; {
		    if packer.loadedFont.count {
			draw_font_test_text();
		    } else {
			packer.fontToAdd = entry.filepath;
		    }
		}

		case .Audio; {
		    audio := entry.audio;
		    
		    minutes := floor(audio.duration / 60.0);
		    ImGui.Text("Audio Duration:    %:%", cast(u32) minutes, audio.duration - (minutes * 60.0));
		    ImGui.Text("Audio Channels:    %", audio.channels);
		    ImGui.Text("Audio Sample Rate: %", audio.sampleRate);
		    
		    ImGui.NewLine();

		    playCursor = ifx CURRENT_STREAM then cast(float) CURRENT_STREAM.play_cursor else 0.0;
		    playCursor = cast(float) playCursor / cast(float) audio.sampleRate;
		    ImGui.SliderFloat("Volume", *CURRENT_AUDIO.volume_scale, 0.0, 1.0);
		    ImGui.SliderFloat("Progress", *playCursor, 0.0, audio.duration, flags = .NoInput);

		    if !packer.audioIsPlaying {
			if ImGui.Button("Play") {
			    CURRENT_AUDIO = load_audio_file(entry.filepath);
			    CURRENT_STREAM = make_stream(*CURRENT_AUDIO, null, .GENERAL_SFX);
			    start_playing(CURRENT_STREAM);
			    packer.audioIsPlaying = true;
			}
		    } else {
			if ImGui.Button("Stop") {
			    stop_stream_abruptly(*CURRENT_AUDIO);
			    CURRENT_AUDIO = .{};
			    packer.audioIsPlaying = false;
			}
		    }
		}

		case; assert(false, "Unimplemented Type for Display");
	    }
	}
	ImGui.EndChild();

	ImGui.SetNextWindowPos(.{ 5.0, windowHeight - 65.0 });
	saveWindowSize := ImGui.ImVec2.{ (windowWidth * 0.5) - 10.0, 60.0 };
	ImGui.BeginChild("Pack Explorer", saveWindowSize, .Border, .NoTitleBar | .NoResize | .NoMove | .NoScrollbar | .NoScrollWithMouse);
	isDirectoryInvalid := !is_directory(packer.project.exportDirectory);
	if isDirectoryInvalid then ImGui.PushStyleColor(ImGui.Col.Text, .{ 1, 0, 0, 1 });
	ImGui.InputText("Export Directory", *packer.project.exportDirectory);
	if isDirectoryInvalid then ImGui.PopStyleColor();
	ImGui.InputText("Project Name", *packer.project.name);
	ImGui.EndChild();
	
	ImGui.SetNextWindowPos(.{ windowWidth * 0.5 + 5.0, windowHeight - 65.0 });
	optionWindowSize := ImGui.ImVec2.{ (windowWidth * 0.5) - 10.0, 60.0 };
	ImGui.BeginChild("Asset Options", optionWindowSize, .Border, .NoTitleBar | .NoResize | .NoMove | .NoScrollbar | .NoScrollWithMouse);
	
	ImGui.BeginDisabled(packer.selectedEntryIndex == -1);
	if ImGui.Button("Rename Asset", ImGui.ImVec2.{ 120, 20 }) {
	    // TODO: 
	}
	ImGui.EndDisabled();
	
	ImGui.SameLine();

	ImGui.BeginDisabled(packer.project.entries.count == 0);
	if ImGui.Button("Export Packs", ImGui.ImVec2.{ 120, 20 }) {
	    construct_packs(packer);
	}
	ImGui.EndDisabled();
	
	ImGui.BeginDisabled(packer.selectedEntryIndex == -1);
	if ImGui.Button("Delete Asset", ImGui.ImVec2.{ 120, 20 }) {
	    array_unordered_remove_by_index(*packer.project.entries, packer.selectedEntryIndex);
	    packer.selectedEntryIndex = -1;
	}
	ImGui.EndDisabled();

	ImGui.SameLine();
	
	ImGui.BeginDisabled(!ALLOW_CORE_BUILDING);
	if ImGui.Button("Export Core", ImGui.ImVec2.{ 120, 20 }) {
	    construct_core_pack(packer);
	}
	ImGui.EndDisabled();
	
	ImGui.EndChild();

	ImGui.End();
	
	ImGui.Render();
	ImGui.ImplOpenGL3_RenderDrawData(ImGui.GetDrawData());
	
	Simp.swap_buffers(window);
	
        deltaTime = seconds_since_init() - lastTime;
        lastTime = seconds_since_init();

	update(cast(float) deltaTime);
        
        reset_temporary_storage();
    }
}

detect_asset_type :: (packer : *PackerState) {
    ext := to_lower_copy(path_extension(packer.entryToAdd.filepath));

    for SupportedFormats {
	if it == ext {
	    packer.entryToAdd.type = cast(AssetType) it_index;
	    return;
	}
    }
}

process_asset_from_file :: (packer : *PackerState) {
    if #complete packer.entryToAdd.type == {
	case .Invalid; {
	    print_color("Type of file for \"%\" cannot be determined.\n", packer.entryToAdd.filepath, color = .HI_RED);
	    packer.entryToAdd = .{};
	}

	case .Mesh; {
	    
	}

	case .Image; {
	    // Load the KTX file and make sure it's valid
	    ktxFile, readSuccess := read_entire_file(packer.entryToAdd.filepath);
	    if !readSuccess {
		free(ktxFile);
		print_color("\n\tFailed to read file \"%\"\n\n", packer.entryToAdd.filepath, color = .HI_RED);
		packer.entryToAdd = .{};
		return;
	    }
	    defer free(ktxFile);
	    
	    texture := New(ktxTexture2);
	    result := ktxTexture2_CreateFromMemory(ktxFile.data, cast(u64) ktxFile.count, .LOAD_IMAGE_DATA_BIT, *texture);
	    if result != .SUCCESS {
		print_color("\n\tFailed to create ktx texture from \"%\" with error: %\n", packer.entryToAdd.filepath, result, color = .HI_RED);
		free(texture);
		packer.entryToAdd = .{};
		return;
	    }

	    packer.entryToAdd.image.width = texture.baseWidth;
	    packer.entryToAdd.image.height = texture.baseHeight;
	    packer.entryToAdd.image.mipLevels = texture.numLevels;
	    
	    // Fill out header info, type is already filled out, offset will be filled out during packing
	    filenameNoExt := path_strip_extension(path_filename(packer.entryToAdd.filepath));
	    packer.entryToAdd.name = copy_string(filenameNoExt);
	    packer.entryToAdd.size = cast(u64) ktxFile.count;
	    assert((packer.entryToAdd.size + size_of(Asset)) <= MAX_ASSET_FILE_SIZE, "Asset is too large for current maximum file size");
	}

	case .JSON; {
	    jsonFile, readSuccess := read_entire_file(packer.entryToAdd.filepath);
	    if !readSuccess {
		free(jsonFile);
		print_color("\n\tFailed to read file \"%\"\n\n", packer.entryToAdd.filepath, color = .HI_RED);
		packer.entryToAdd = .{};
		return;
	    }
	    defer free(jsonFile);

	    // Fill out header info, type is already filled out, offset will be filled out during packing
	    filenameNoExt := path_strip_extension(path_filename(packer.entryToAdd.filepath));
	    packer.entryToAdd.name = copy_string(filenameNoExt);
	    packer.entryToAdd.size = cast(u64) jsonFile.count;
	    assert((packer.entryToAdd.size + size_of(Asset)) <= MAX_ASSET_FILE_SIZE, "Asset is too large for current maximum file size");
	}

	case .Font; {
	    ttfFile, readSuccess := read_entire_file(packer.entryToAdd.filepath);
	    if !readSuccess {
		free(ttfFile);
		print_color("\n\tFailed to read file \"%\"\n\n", packer.entryToAdd.filepath, color = .HI_RED);
		packer.entryToAdd = .{};
		return;
	    }
	    defer free(ttfFile);

	    // Fill out header info, type is already filled out, offset will be filled out during packing
	    filenameNoExt := path_strip_extension(path_filename(packer.entryToAdd.filepath));
	    packer.entryToAdd.name = copy_string(filenameNoExt);
	    packer.entryToAdd.size = cast(u64) ttfFile.count;
	    assert((packer.entryToAdd.size + size_of(Asset)) <= MAX_ASSET_FILE_SIZE, "Asset is too large for current maximum file size");

	    packer.loadedFont = "";
	}
	
	case .Audio; {
	    wavFile, readSuccess := read_entire_file(packer.entryToAdd.filepath);
	    if !readSuccess {
		free(wavFile);
		print_color("\n\tFailed to read file \"%\"\n\n", packer.entryToAdd.filepath, color = .HI_RED);
		packer.entryToAdd = .{};
		return;
	    }
	    defer free(wavFile);
	    
	    audio := load_audio_file(packer.entryToAdd.filepath);
	    packer.entryToAdd.audio.duration = cast(float) (audio.buffer.count / size_of(u16)) / cast(float) audio.sampling_rate / cast(float) audio.nchannels;
	    packer.entryToAdd.audio.channels = audio.nchannels;
	    packer.entryToAdd.audio.sampleRate = audio.sampling_rate;
	    
	    // Fill out header info, type is already filled out, offset will be filled out during packing
	    filenameNoExt := path_strip_extension(path_filename(packer.entryToAdd.filepath));
	    packer.entryToAdd.name = copy_string(filenameNoExt);
	    packer.entryToAdd.size = cast(u64) wavFile.count;
	    assert((packer.entryToAdd.size + size_of(Asset)) <= MAX_ASSET_FILE_SIZE, "Asset is too large for current maximum file size");
	}

	case .Video; {
	    
	}
    }
}

construct_packs :: (packer : *PackerState) {
    path := packer.project.exportDirectory;
    if path.count == 0 || !is_directory(path) {
	path = get_packaged_assets_path();
    }

    path_overwrite_separators(path, #char "/");
    if !ends_with(path, "/") then path = tprint("%/", path);
    
    directory : DirectoryFile;
    directory.fileCode = pack_file_code(ASSET_FILE_CODE);
    directory.encryptSeed = 0; // 0 is not a valid encryption seed so the files won't be encrypted
    directory.itemCount = packer.project.entries.count;
    directoryBuilder : String_Builder;
    init_string_builder(*directoryBuilder, size_of(DirectoryFile) + (directory.itemCount * size_of(DirectoryItem)));
    simple_memcpy(*directoryBuilder, directory);

    currentFileIndex : u8;
    currentFileSize : u64;
    currentFile : *File;
    packBuilder : String_Builder;
    for packer.project.entries {
	if currentFile && (MAX_ASSET_FILE_SIZE - currentFileSize) < it.size {
	    file_write(currentFile, *packBuilder);
	    file_close(currentFile);
    	    print("\tWrote %\n", tprint("%_%.%", packer.project.name, currentFileIndex, ASSET_PACK_FILE_EXTENSION));
	    
	    currentFile = null;
	    currentFileSize = 0;
	    currentFileIndex += 1;
	}
	
	if !currentFile {
	    currentFile = *file_open(tprint("%1%2_%.%", path, packer.project.name, currentFileIndex, ASSET_PACK_FILE_EXTENSION), true);
	    init_string_builder(*packBuilder, MAX_ASSET_FILE_SIZE);
	}
	
	item : DirectoryItem;
	memcpy(item.name.data, it.name.data, ifx item.name.count < it.name.count then item.name.count else it.name.count);
	item.type = it.type;
	item.file = currentFileIndex;
	item.offset = currentFileSize;
	assert(it.filepath.count <= item.filepath.count);
	memcpy(item.filepath.data, it.filepath.data, it.filepath.count);
	simple_memcpy(*directoryBuilder, item);

	header : AssetHeader;
	memcpy(header.name.data, it.name.data, it.name.count);
	header.type = it.type;
	header.size = it.size;
	simple_memcpy(*packBuilder, header);
	
	assetFile, readSuccess := read_entire_file(it.filepath);
	assert(readSuccess, tprint("Failed to load \"%\" during construction", it.filepath));
	append(*packBuilder, assetFile);
	currentFileSize += cast(u64) (size_of(AssetHeader) + assetFile.count);

	print("\tWrote % to %\n", cast(string) it.name, tprint("%_%.%", packer.project.name, currentFileIndex, ASSET_PACK_FILE_EXTENSION));
    }

    // Write last asset pack
    file_write(currentFile, *packBuilder);
    file_close(currentFile);
    print("\tWrote %\n", tprint("%_%.%", packer.project.name, currentFileIndex, ASSET_PACK_FILE_EXTENSION));

    // Write directory file
    write_entire_file(tprint("%1%2.%", path, packer.project.name, ASSET_DIR_FILE_EXTENSION), *directoryBuilder);
    print("\tWrote %\n", tprint("%.%", packer.project.name, ASSET_DIR_FILE_EXTENSION));
}

construct_core_pack :: (packer : *PackerState) {
    path := packer.project.exportDirectory;
    if path.count == 0 || !is_directory(path) {
	path = get_raw_assets_path();
    }

    path_overwrite_separators(path, #char "/");
    if !ends_with(path, "/") then path = tprint("%/", path);
    
    packBuilder : String_Builder;
    init_string_builder(*packBuilder);

    add_core_asset :: (packBuilder : *String_Builder, type : AssetType, name : string, path : string) {
	header : AssetHeader;
	memcpy(header.name.data, name.data, name.count);
	header.type = type;

	assetFile, readSuccess := read_entire_file(tprint(path, "C:/work/bs_modules/loam/data/"));
	assert(readSuccess, "Failed to load core % file: %", enum_value_to_name(type), name);

	header.size = cast(u64) assetFile.count;
	
	simple_memcpy(packBuilder, header);
	append(packBuilder, assetFile);

	print("\tWrote (%) % to loam_core.%\n", type, name, ASSET_CORE_FILE_EXTENSION);
    }

    add_core_asset(*packBuilder, .Font,  "internal",      "%fonts/internal.ttf");
    add_core_asset(*packBuilder, .Font,  "internal_mono", "%fonts/internal_mono.ttf");
    add_core_asset(*packBuilder, .Image, "loam_splash",   "%images/loam_splash.ktx2");
    add_core_asset(*packBuilder, .Audio, "loam_splash",   "%audio/loam_splash.wav");
    
    writeSuccess := write_entire_file(tprint("%loam_core.%", packer.project.exportDirectory, ASSET_CORE_FILE_EXTENSION), *packBuilder);
    assert(writeSuccess, "Failed to write core assets file");
    print("\tWrote loam_core.%\n", ASSET_CORE_FILE_EXTENSION);
}

draw_font_test_text :: () {
    if FONT_SMALL {
	ImGui.NewLine();
	
	ImGui.PushFont(FONT_SMALL);
	ImGui.Text(TEST_STRING);
	ImGui.PopFont();
    }

    if FONT_MEDIUM {
	ImGui.NewLine();
	
	ImGui.PushFont(FONT_MEDIUM);
	ImGui.Text(to_upper_copy(TEST_STRING));
	ImGui.PopFont();
    }

    if FONT_BIG {
	ImGui.NewLine();
	
	ImGui.PushFont(FONT_BIG);
	ImGui.Text(to_lower_copy(TEST_STRING));
	ImGui.PopFont();
    }
}

// NOTE: This must match AssetType
SupportedFormats :: string.[
    "",
    "glb",  // Mesh
    "ktx2", // Image
    "json", // JSON
    "ttf",  // Font
    "wav",  // Audio
    "mp4",  // Video
];

#scope_file

#import "loam/code"("loam_assetpacker", IS_DEV);
#insert EXTRA_IMPORTS;
#import "Print_Color"()(true);

GL :: #import "GL";
#import "stb_image";
#import "Sound_Player_bs842";
