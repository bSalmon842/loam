/*
Project: Loam
File: asset_packer.jai
Author: Brock Salmon
Created: 24MAY2025
*/

windowWidth  := 1280;
windowHeight := 720;
deltaTime : float64;

// TODO: Make sure that assets with the same name are impossible

// NOTE: We set this for get_packaged_assets_path as we will always be packaging into the dev data folders
IS_DEV :: true;

// Font Info
TEST_STRING :: "Sphinx of Black Quartz, judge my vow\0";
FONT_SMALL  : *ImGui.ImFont;
FONT_MEDIUM : *ImGui.ImFont;
FONT_BIG    : *ImGui.ImFont;

CURRENT_AUDIO : Sound_Data;
CURRENT_STREAM : *Sound_Stream;
playCursor : float;

State :: enum {
    View_Packet; // if opened with a specific packet file to view it
    Make_Packets; // if opened with a dir file or without any file
    Add_Asset; // if dragging an asset onto the window
}

AssetBeingAdded :: struct {
    filepath : string;
    asset    : AssetHeader;
}

PackerState :: struct {
    state := State.Make_Packets;
    pendingAdd : AssetBeingAdded;

    assets : [..] AssetBeingAdded;
    selectedAssetIndex : s64 = -1;
    glTexture : u32;

    fontToAdd  : string;
    loadedFont : string;

    audioIsPlaying : bool;
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
    
    startArgs := get_command_line_arguments();
    for startArgs {
	if ends_with(it, tprint(".%", ASSET_DIR_FILE_EXTENSION)) {
	    open_from_dir_file(packer, it);
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
		    if packer.state == .Make_Packets && it.files.count == 1 {
			packer.state = .Add_Asset;
			packer.pendingAdd.filepath = copy_string(it.files[0]);
			detect_asset_type(packer);
			process_asset_from_file(packer);
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
	
	ImGui.ImplOpenGL3_NewFrame();
	ImGui.ImplJai_NewFrame();
	ImGui.NewFrame();

	

	Simp.clear_render_target(0.1, 0.1, 0.1, 1);
	
	if packer.state == {
	    case .Make_Packets; {
		// Asset Table
		ImGui.SetNextWindowPos(.{ 5, 5 });
		ImGui.SetNextWindowSize(.{ windowWidth * 0.5 - 10.0, windowHeight - 50.0 });
		ImGui.Begin("Asset List Window", flags = .NoTitleBar | .NoResize | .NoMove);
		ImGui.BeginTable("Asset List", 3, flags = .RowBg | .Borders);
		ImGui.TableSetupColumn("Name");
		ImGui.TableSetupColumn("Type");
		ImGui.TableSetupColumn("Size");

		ImGui.TableNextRow(.Headers);
		ImGui.TableNextColumn();
		ImGui.Text("Name");
		ImGui.TableNextColumn();
		ImGui.Text("Type");
		ImGui.TableNextColumn();
		ImGui.Text("Size");

		for * packer.assets {
		    ImGui.TableNextRow();
		    ImGui.TableNextColumn();
		    ImGui.Text(cast(string) it.asset.name);
		    ImGui.TableNextColumn();
		    ImGui.Text("%", it.asset.type);
		    ImGui.TableNextColumn();
		    ImGui.Text(to_size_string(it.asset.size));

		    ImGui.SameLine();
		    if ImGui.Selectable(tprint("##row%_selectable\0", it_index).data, flags = .SpanAllColumns | .AllowItemOverlap) {
			packer.selectedAssetIndex = it_index;
			asset := *packer.assets[packer.selectedAssetIndex];
			if asset.asset.type == {
			    case .Image; {
				GL.glGenTextures(1, *packer.glTexture);
				GL.glBindTexture(GL.GL_TEXTURE_2D, packer.glTexture);
				GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MIN_FILTER, GL.GL_LINEAR);
				GL.glTexParameteri(GL.GL_TEXTURE_2D, GL.GL_TEXTURE_MAG_FILTER, GL.GL_LINEAR);
				GL.glPixelStorei(GL.GL_UNPACK_ROW_LENGTH, 0);
				
				pngFilepath := join(path_strip_extension(asset.filepath), ".png");
				imageWidth, imageHeight, channels : s32;
				imageData := stbi_load(to_c_string(pngFilepath), *imageWidth, *imageHeight, *channels, 4);
				GL.glTexImage2D(GL.GL_TEXTURE_2D, 0, GL.GL_RGBA, xx imageWidth, xx imageHeight, 0, GL.GL_RGBA, GL.GL_UNSIGNED_BYTE, imageData);
				stbi_image_free(imageData);
			    }
			}
		    }
		}
		
		ImGui.EndTable();
		ImGui.End();

		ImGui.SetNextWindowPos(.{ windowWidth * 0.5 + 5.0, 5 });
		windowSize := ImGui.ImVec2.{ (windowWidth * 0.5) - 10.0, windowHeight - 50.0 };
		ImGui.SetNextWindowSize(windowSize);
		ImGui.Begin("Asset Inspector", flags = .NoTitleBar | .NoResize | .NoMove | .HorizontalScrollbar);
		if packer.selectedAssetIndex != -1 {
		    asset := *packer.assets[packer.selectedAssetIndex];
		    if asset.asset.type == {
			case .Image; {
			    image := asset.asset.Image;

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
			    ImGui.Text("Name: %", cast(string) asset.asset.name);
			    ImGui.Text("Width: %", image.width);
			    ImGui.SameLine();
			    ImGui.Text("\tHeight: %", image.height);
			    ImGui.Text("Mip Levels: %", image.mipLevels);
			}
			
			case .Font; {
			    if packer.loadedFont.count {
				draw_font_test_text();
			    } else {
				packer.fontToAdd = asset.filepath;
			    }
			}

			case .Audio; {
			    audio := asset.asset.Audio;
			    
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
				    CURRENT_AUDIO = load_audio_file(asset.filepath);
				    CURRENT_STREAM = make_stream(*CURRENT_AUDIO, .GENERAL_SFX);
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
		ImGui.End();

		ImGui.SetNextWindowPos(.{ 5.0, windowHeight - 40.0 });
		saveWindowSize := ImGui.ImVec2.{ (windowWidth * 0.5) - 10.0, 35.0 };
		ImGui.SetNextWindowSize(saveWindowSize);
		ImGui.Begin("Pack Explorer", flags = .NoTitleBar | .NoResize | .NoMove | .NoScrollbar | .NoScrollWithMouse);
		if ImGui.Button("Save Asset Packs", ImGui.ImVec2.{ 120, 20 }) {
		    construct_packs(packer);
		    construct_core_pack();
		}
		ImGui.SameLine();
		if ImGui.Button("Build Core Pack", ImGui.ImVec2.{ 120, 20}) {
		    construct_core_pack();
		}
		ImGui.End();

		ImGui.SetNextWindowPos(.{ windowWidth * 0.5 + 5.0, windowHeight - 40.0 });
		optionWindowSize := ImGui.ImVec2.{ (windowWidth * 0.5) - 10.0, 35.0 };
		ImGui.SetNextWindowSize(optionWindowSize);
		ImGui.Begin("Asset Options", flags = .NoTitleBar | .NoResize | .NoMove | .NoScrollbar | .NoScrollWithMouse);
		if ImGui.Button("Rename", ImGui.ImVec2.{ 120, 20 }) {
		    // TODO: 
		}
		ImGui.SameLine();
		if ImGui.Button("Delete", ImGui.ImVec2.{ 120, 20 }) {
		    array_unordered_remove_by_index(*packer.assets, packer.selectedAssetIndex);
		    packer.selectedAssetIndex = -1;
		}
		ImGui.End();
	    }
	    
	    case .Add_Asset; {
		ImGui.SetNextWindowPos(.{ windowWidth * 0.125, windowHeight * 0.125 });
		ImGui.SetNextWindowSize(.{ windowWidth * 0.75, windowHeight * 0.75 });
		ImGui.Begin("Add Asset Window", flags = .NoResize | .NoMove | .NoCollapse);
		windowSize := ImGui.GetWindowSize();
		ImGui.Text("Filepath: %", path_strip_filename(packer.pendingAdd.filepath));
		ImGui.Text("Original Filename: %", path_filename(packer.pendingAdd.filepath));
		ImGui.Text("Detected Asset Type: %", packer.pendingAdd.asset.type);

		ImGui.NewLine();

		display_for_asset_type(packer, *packer.pendingAdd);
		
		addButtonSize := ImGui.ImVec2.{ 90, 30 };
		ImGui.SetCursorPos(ImGui.ImVec2.{ windowSize.x - (addButtonSize.x + 10), windowSize.y - (addButtonSize.y + 10) });
		// TODO: Check for overwrite
		if ImGui.Button("Add Asset", addButtonSize) {
		    stop_stream_abruptly(*CURRENT_AUDIO);
		    CURRENT_AUDIO = .{};
		    packer.audioIsPlaying = false;
		    
		    array_add(*packer.assets, packer.pendingAdd);
		    packer.state = .Make_Packets;
		    packer.pendingAdd = .{};
		}
		ImGui.End();
	    }
	}

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
    ext := to_lower_copy(path_extension(packer.pendingAdd.filepath));

    for SupportedFormats {
	if it == ext {
	    packer.pendingAdd.asset.type = cast(AssetType) it_index;
	    return;
	}
    }
}

process_asset_from_file :: (packer : *PackerState) {
    if #complete packer.pendingAdd.asset.type == {
	case .Invalid; {
	    print_color("Type of file for \"%\" cannot be determined.\n", packer.pendingAdd.filepath, color = .HI_RED);
	    packer.state = .Make_Packets;
	    packer.pendingAdd = .{};
	}

	case .Mesh; {
	    
	}

	case .Image; {
	    // Load the KTX file and make sure it's valid
	    ktxFile, readSuccess := read_entire_file(packer.pendingAdd.filepath);
	    if !readSuccess {
		free(ktxFile);
		print_color("\n\tFailed to read file \"%\"\n\n", packer.pendingAdd.filepath, color = .HI_RED);
		packer.state = .Make_Packets;
		packer.pendingAdd = .{};
		return;
	    }
	    defer free(ktxFile);
	    
	    texture := New(ktxTexture2);
	    result := ktxTexture2_CreateFromMemory(ktxFile.data, cast(u64) ktxFile.count, .LOAD_IMAGE_DATA_BIT | .CHECK_GLTF_BASISU_BIT, *texture);
	    if result != .SUCCESS {
		print_color("\n\tFailed to create ktx texture from \"%\" with error: %\n\n", packer.pendingAdd.filepath, result, color = .HI_RED);
		free(texture);
		packer.state = .Make_Packets;
		packer.pendingAdd = .{};
		return;
	    }

	    // Fill out header info, type is already filled out, offset will be filled out during packing
	    filenameNoExt := path_strip_extension(path_filename(packer.pendingAdd.filepath));
	    memcpy(packer.pendingAdd.asset.name.data, filenameNoExt.data, min(packer.pendingAdd.asset.name.count, filenameNoExt.count));
	    packer.pendingAdd.asset.version = 1; // This will get updated later if this asset is overwriting an existing asset
	    packer.pendingAdd.asset.size = cast(u64) ktxFile.count;
	    assert((packer.pendingAdd.asset.size + size_of(Asset)) <= MAX_ASSET_FILE_SIZE, "Asset is too large for current maximum file size");

	    // Fill out asset info
	    packer.pendingAdd.asset.Image.width = texture.baseWidth;
	    packer.pendingAdd.asset.Image.height = texture.baseHeight;
	    if texture.numLevels == 0 {
		print_color("\n\tktx texture \"%\" had 0 mip levels\n\n", packer.pendingAdd.filepath, result, color = .HI_RED);
		free(texture);
		packer.state = .Make_Packets;
		packer.pendingAdd = .{};
		return;
	    }
	    packer.pendingAdd.asset.Image.mipLevels = texture.numLevels;

	    if !ktxTexture2_NeedsTranscoding(texture) {
		print_color("\n\tTexture \"%\" is not Basis encoded.\n\n", packer.pendingAdd.filepath, color = .HI_RED);
		free(texture);
		packer.state = .Make_Packets;
		packer.pendingAdd = .{};
		return;
	    }
	}

	case .Font; {
	    ttfFile, readSuccess := read_entire_file(packer.pendingAdd.filepath);
	    if !readSuccess {
		free(ttfFile);
		print_color("\n\tFailed to read file \"%\"\n\n", packer.pendingAdd.filepath, color = .HI_RED);
		packer.state = .Make_Packets;
		packer.pendingAdd = .{};
		return;
	    }
	    defer free(ttfFile);

	    // Fill out header info, type is already filled out, offset will be filled out during packing
	    filenameNoExt := path_strip_extension(path_filename(packer.pendingAdd.filepath));
	    memcpy(packer.pendingAdd.asset.name.data, filenameNoExt.data, min(packer.pendingAdd.asset.name.count, filenameNoExt.count));
	    packer.pendingAdd.asset.version = 1; // This will get updated later if this asset is overwriting an existing asset
	    packer.pendingAdd.asset.size = cast(u64) ttfFile.count;
	    assert((packer.pendingAdd.asset.size + size_of(Asset)) <= MAX_ASSET_FILE_SIZE, "Asset is too large for current maximum file size");

	    packer.loadedFont = "";
	}

	case .Lang; {
	    
	}

	case .Audio; {
	    wavFile, readSuccess := read_entire_file(packer.pendingAdd.filepath);
	    if !readSuccess {
		free(wavFile);
		print_color("\n\tFailed to read file \"%\"\n\n", packer.pendingAdd.filepath, color = .HI_RED);
		packer.state = .Make_Packets;
		packer.pendingAdd = .{};
		return;
	    }
	    defer free(wavFile);

	    // Fill out header info, type is already filled out, offset will be filled out during packing
	    filenameNoExt := path_strip_extension(path_filename(packer.pendingAdd.filepath));
	    memcpy(packer.pendingAdd.asset.name.data, filenameNoExt.data, min(packer.pendingAdd.asset.name.count, filenameNoExt.count));
	    packer.pendingAdd.asset.version = 1; // This will get updated later if this asset is overwriting an existing asset
	    packer.pendingAdd.asset.size = cast(u64) wavFile.count;
	    assert((packer.pendingAdd.asset.size + size_of(Asset)) <= MAX_ASSET_FILE_SIZE, "Asset is too large for current maximum file size");

	    audio := load_audio_file(packer.pendingAdd.filepath);
	    packer.pendingAdd.asset.Audio.duration = cast(float) (audio.buffer.count / size_of(u16)) / cast(float) audio.sampling_rate / cast(float) audio.nchannels;
	    packer.pendingAdd.asset.Audio.channels = audio.nchannels;
	    packer.pendingAdd.asset.Audio.sampleRate = audio.sampling_rate;
	}

	case .Video; {
	    
	}
    }
}

display_for_asset_type :: (packer : *PackerState, loadedAsset : *AssetBeingAdded) {
    if #complete loadedAsset.asset.type == {
	case .Invalid;

	case .Mesh; {
	    // TODO: 
	}

	case .Image; {
	    ImGui.Text("Image Name:      ");
	    ImGui.SameLine();
	    ImGui.PushItemWidth(250);
	    ImGui.InputText("##imagename", loadedAsset.asset.name.data, loadedAsset.asset.name.count);
	    ImGui.PopItemWidth();
	    
	    ImGui.Text("Image Width:      %", loadedAsset.asset.Image.width);
	    ImGui.Text("Image Height:     %", loadedAsset.asset.Image.height);
	    ImGui.Text("Image Mip Levels: %", loadedAsset.asset.Image.mipLevels);
	}

	case .Font; {
	    ImGui.Text("Font Name:       ");
	    ImGui.SameLine();
	    ImGui.PushItemWidth(250);
	    ImGui.InputText("##fontname", loadedAsset.asset.name.data, loadedAsset.asset.name.count);
	    ImGui.PopItemWidth();

	    if packer.loadedFont.count {
		draw_font_test_text();
	    } else {
		packer.fontToAdd = loadedAsset.filepath;
	    }
	}

	case .Lang; {
	    // TODO: 
	}

	case .Audio; {
	    ImGui.Text("Audio Name:      ");
	    ImGui.SameLine();
	    ImGui.PushItemWidth(250);
	    ImGui.InputText("##audioname", loadedAsset.asset.name.data, loadedAsset.asset.name.count);
	    ImGui.PopItemWidth();

	    minutes := floor(loadedAsset.asset.Audio.duration / 60.0);
	    ImGui.Text("Audio Duration:    %:%", cast(u32) minutes, loadedAsset.asset.Audio.duration - (minutes * 60.0));
	    ImGui.Text("Audio Channels:    %", loadedAsset.asset.Audio.channels);
	    ImGui.Text("Audio Sample Rate: %", loadedAsset.asset.Audio.sampleRate);
	    
	    ImGui.NewLine();

	    playCursor = ifx CURRENT_STREAM then cast(float) CURRENT_STREAM.play_cursor else 0.0;
	    playCursor = cast(float) playCursor / cast(float) loadedAsset.asset.Audio.sampleRate;
	    ImGui.SliderFloat("Volume", *CURRENT_AUDIO.volume_scale, 0.0, 1.0);
	    ImGui.SliderFloat("Progress", *playCursor, 0.0, loadedAsset.asset.Audio.duration, flags = .NoInput);

	    if !packer.audioIsPlaying {
		if ImGui.Button("Play") {
		    CURRENT_AUDIO = load_audio_file(loadedAsset.filepath);
		    CURRENT_STREAM = make_stream(*CURRENT_AUDIO, .GENERAL_SFX);
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

	case .Video; {
	    // TODO: Video player
	}
    }
}

open_from_dir_file :: (packerState : *PackerState, dirFile : string) {
    dirContents, readSuccess := read_entire_file(dirFile);
    if readSuccess {
	dirFile := cast(*DirectoryFile) dirContents.data;
	assert(dirFile.fileCode == pack_file_code(ASSET_FILE_CODE));

	for 0 .. dirFile.itemCount-1 {
    	    dirItem := cast(*DirectoryItem) (dirContents.data + size_of(DirectoryFile) + (size_of(DirectoryItem) * it));
	    
	    filepath := to_string(dirItem.filepath.data);

	    packName := tprint("%1%2_%.%", get_packaged_assets_path(), APP_NAME, dirItem.file, ASSET_PACK_FILE_EXTENSION);
	    packContents, packSuccess := read_entire_file(packName);
	    if packSuccess {
		header := cast(*AssetHeader) (packContents.data + dirItem.offset);
		array_add(*packerState.assets, .{ filepath, header.* });

		free(packContents.data);
	    }
	}
	
	free(dirContents.data);
    }
}

construct_packs :: (packer : *PackerState) {
    existingFiles := file_list(get_packaged_assets_path());
    for existingFiles {
	if !file_delete(it) then print_color("\n\tFailed to delete file \"%\"\n\n", it, color = .HI_RED);
    }

    directory : DirectoryFile;
    directory.fileCode = pack_file_code(ASSET_FILE_CODE);
    directory.encryptSeed = 0; // 0 is not a valid encryption seed so the files won't be encrypted
    directory.itemCount = packer.assets.count;
    directoryBuilder : String_Builder;
    init_string_builder(*directoryBuilder, size_of(DirectoryFile) + (packer.assets.count * size_of(DirectoryItem)));
    simple_memcpy(*directoryBuilder, directory);

    currentFileIndex : u8;
    currentFileSize : u64;
    currentFile : *File;
    packBuilder : String_Builder;
    for packer.assets {
	if currentFile && (MAX_ASSET_FILE_SIZE - currentFileSize) < it.asset.size {
	    file_write(currentFile, *packBuilder);
	    file_close(currentFile);
    	    print("\tWrote %\n", tprint("%_%.%", APP_NAME, currentFileIndex, ASSET_PACK_FILE_EXTENSION));
	    
	    currentFile = null;
	    currentFileSize = 0;
	    currentFileIndex += 1;
	}
	
	if !currentFile {
	    currentFile = *file_open(tprint("%1%2_%.%", get_packaged_assets_path(), APP_NAME, currentFileIndex, ASSET_PACK_FILE_EXTENSION), true);
	    init_string_builder(*packBuilder, MAX_ASSET_FILE_SIZE);
	}
	
	item : DirectoryItem;
	memcpy(item.name.data, it.asset.name.data, it.asset.name.count);
	item.type = it.asset.type;
	item.file = currentFileIndex;
	item.offset = currentFileSize;
	assert(it.filepath.count <= item.filepath.count);
	memcpy(item.filepath.data, it.filepath.data, it.filepath.count);
	simple_memcpy(*directoryBuilder, item);

	simple_memcpy(*packBuilder, it.asset);
	assetFile, readSuccess := read_entire_file(it.filepath);
	assert(readSuccess, tprint("Failed to load \"%\" during construction", it.filepath));
	append(*packBuilder, assetFile);
	currentFileSize += cast(u64) (size_of(AssetHeader) + assetFile.count);

	print("\tWrote % to %\n", cast(string) it.asset.name, tprint("%_%.%", APP_NAME, currentFileIndex, ASSET_PACK_FILE_EXTENSION));
    }

    // Write last asset pack
    file_write(currentFile, *packBuilder);
    file_close(currentFile);
    print("\tWrote %\n", tprint("%_%.%", APP_NAME, currentFileIndex, ASSET_PACK_FILE_EXTENSION));

    // Write directory file
    write_entire_file(tprint("%1%2.%", get_packaged_assets_path(), APP_NAME, ASSET_DIR_FILE_EXTENSION), *directoryBuilder);
    print("\tWrote %\n", tprint("%.%", APP_NAME, ASSET_DIR_FILE_EXTENSION));
}

construct_core_pack :: () {
    packBuilder : String_Builder;
    init_string_builder(*packBuilder);

    add_core_font :: (packBuilder : *String_Builder, name : string, path : string) {
	header : AssetHeader;
	memcpy(header.name.data, name.data, name.count);
	header.type = .Font;
	header.version = 1;

	assetFile, readSuccess := read_entire_file(tprint(path, get_raw_assets_path()));
	assert(readSuccess, "Failed to load core font file: %", name);

	header.size = cast(u64) assetFile.count;
	
	simple_memcpy(packBuilder, header);
	append(packBuilder, assetFile);
    }

    add_core_font(*packBuilder, "internal", "%fonts/internal.ttf");
    add_core_font(*packBuilder, "internal_mono", "%fonts/internal_mono.ttf");
    
    writeSuccess := write_entire_file(tprint("%loam_core.%", get_packaged_assets_path(), ASSET_CORE_FILE_EXTENSION), *packBuilder);
    assert(writeSuccess, "Failed to write core assets file");
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
    "ttf",  // Font
    "lang", // Lang
    "wav",  // Audio
    "mp4",  // Video
];

#scope_file

#load "../engine.jai";

#import "Basic";
#import "File";
#import "File_Utilities";
GL :: #import "GL";
#import "Hash_Table";
#import "Input";
#import "Print_Color";
Simp :: #import "Simp";
#import "Sound_Player";
#import "stb_image";
#import "String";
#import "Window_Creation";
Windows :: #import "Windows";

ImGui :: #import "ImGui_1_9";
