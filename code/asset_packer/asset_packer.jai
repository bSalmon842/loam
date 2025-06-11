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
IS_DEBUG :: true;

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
}

main :: () {
    Windows.SetProcessDPIAware();
    Windows.timeBeginPeriod(1);

    make_log_file("loam_assetpacker", .YEAR | .MONTH | .DAY | .HOUR | .MINUTE);

    window := create_window(windowWidth, windowHeight, "loam_assetpacker");

    Windows.DragAcceptFiles(window, cast(Windows.BOOL) true);
    Simp.set_render_target(window);

    ImGui.CreateContext();
    ImGui.ImplJai_Init(window);
    ImGui.ImplOpenGL3_Init();
    
    packer := New(PackerState);
    
    startArgs := get_command_line_arguments();
    for startArgs {
	if ends_with(it, tprint(".%", ASSET_DIR_FILE_EXTENSION)) {
//	    open_from_dir_file(it);
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
			if asset.asset.type == .Image {
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
		
		ImGui.EndTable();
		ImGui.End();

		ImGui.SetNextWindowPos(.{ windowWidth * 0.5 + 5.0, 5 });
		windowSize := ImGui.ImVec2.{ (windowWidth * 0.5) - 10.0, windowHeight - 50.0 };
		ImGui.SetNextWindowSize(windowSize);
		ImGui.Begin("Asset Inspector", flags = .NoTitleBar | .NoResize | .NoMove);
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
		}
		ImGui.End();

		ImGui.SetNextWindowPos(.{ windowWidth * 0.5 + 5.0, windowHeight - 40.0 });
		optionWindowSize := ImGui.ImVec2.{ (windowWidth * 0.5) - 10.0, 35.0 };
		ImGui.SetNextWindowSize(optionWindowSize);
		ImGui.Begin("Asset Options", flags = .NoTitleBar | .NoResize | .NoMove | .NoScrollbar | .NoScrollWithMouse);
		if ImGui.Button("Rename", ImGui.ImVec2.{ 120, 20 }) {
		    
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

		display_for_asset_type(*packer.pendingAdd);
		
		addButtonSize := ImGui.ImVec2.{ 90, 30 };
		ImGui.SetCursorPos(ImGui.ImVec2.{ windowSize.x - (addButtonSize.x + 10), windowSize.y - (addButtonSize.y + 10) });
		// TODO: Check for overwrite
		if ImGui.Button("Add Asset", addButtonSize) {
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

	case .Lang; {
	    
	}

	case .Audio; {
	    
	}

	case .Video; {
	    
	}
    }
}

display_for_asset_type :: (loadedAsset : *AssetBeingAdded) {
    if #complete loadedAsset.asset.type == {
	case .Invalid;

	case .Mesh; {
	    
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

	case .Lang; {
	    
	}

	case .Audio; {
	    // TODO: Audio player
	}

	case .Video; {
	    // TODO: Video player
	}
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
	simple_memcpy(*directoryBuilder, item);

	simple_memcpy(*packBuilder, it.asset);
	assetFile, readSuccess := read_entire_file(it.filepath);
	assert(readSuccess, tprint("Failed to load \"%\" during construction", it.filepath));
	append(*packBuilder, assetFile);
	currentFileSize += cast(u64) (size_of(Asset) + assetFile.count);

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

// NOTE: This must match AssetType
SupportedFormats :: string.[
    "",
    "glb",
    "ktx2",
    "lang",
    "wav",
    "mp4",
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
#import "stb_image";
#import "String";
#import "Window_Creation";
Windows :: #import "Windows";

ImGui :: #import "ImGui_1_9";
