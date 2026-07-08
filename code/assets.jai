/*
Project: Loam
File: assets.jai
Author: Brock Salmon
Created: 22MAY2025
*/

// NOTE: As of 05/02/2026 we got rid of the 'core' signifier, if we want this back later we need to check if the asset came from an 'xx_engine_xx' lp file

///////////////////////////////////////////////////////
// ASSET MAPPING //////////////////////////////////////
///////////////////////////////////////////////////////

AssetMap :: Table(string, *AssetMapItem);
AssetMapItem :: struct {
    file     : string;
    packType : AssetPackType;
    offset   : s64;
}

load_and_merge_asset_maps :: (gameCode : string, paths : [] string) -> string {
    fusedJSON : String_Builder;
    init_string_builder(*fusedJSON);
    append(*fusedJSON, "{");
    for paths {
	filename := path_strip_extension(path_filename(it));
	
	// Verify the filenames are correct with the game loading it
	filenameParts := split(filename, "_");
	assert(filenameParts[0] == "a", "First part of pack filename is expected to be 'a' for asset files");
	assert(filenameParts[1] == gameCode || filenameParts[1] == "LOAM", "Second part of pack filename is expected to be the game code (or LOAM for engine core assets");
	isCorrectType := false;
	for enum_names(AssetPackType) {
	    if to_lower_copy(it) == filenameParts[2] {
		isCorrectType = true;
		break;
	    }
	}
	assert(isCorrectType, "Third part of pack filename is expected to be the pack type (engine, game, mod, or expac");
	
	rawMapContents, readRawMapSuccess := read_file(it);
	if !readRawMapSuccess {
	    log(.FATAL, "Failed to read map file: %", it);
	}

	mapDecompSuccess, mapContents := decompress_data(rawMapContents);
	if !mapDecompSuccess {
	    log(.FATAL, "Failed to decompress map file: %", it);
	}

	append(*fusedJSON, tprint("\"%\" : ", filename));
	append(*fusedJSON, mapContents);
	
	if it_index != paths.count-1 {
	    append(*fusedJSON, ",");
	}
	
	free(mapContents);
    }
    append(*fusedJSON, "}");
    return builder_to_string(*fusedJSON);
}

AssetSearch :: struct {
    mapPaths : [..] string;
    packagePaths : [..] string;
}

get_asset_files_in_folder :: (userData : *void, dirName : *u8, fName : *u8) -> SDL.EnumerationResult #c_call {
    push_context {
	results := cast(*AssetSearch) userData;
	fileName := to_string(fName);
	dirPath := to_string(dirName);
	log(.INFO, "Found file: % in %", fileName, dirPath);
	if ends_with(fileName, ".lm") {
	    fullPath := tprint("%1%2", dirPath, fileName);
	    array_add(*results.mapPaths, fullPath);
	} else if ends_with(fileName, ".lp") {
	    fullPath := tprint("%1%2", dirPath, fileName);
	    array_add(*results.packagePaths, fullPath);
	}
	
	return .CONTINUE;
    }
}

load_asset_map :: (gameCode : string) -> *AssetMap {
    basePath := get_packaged_assets_path();
    
    searchResults : AssetSearch;
    if !SDL.enumerate_directory(to_c_string(basePath), get_asset_files_in_folder, *searchResults) {
	log(.FATAL, "Failed to enumerate directory \"%\" with SDL error: %", basePath, to_string(SDL.get_error()));
    }

    packagePaths := searchResults.packagePaths;
    mapPaths := searchResults.mapPaths;

    log(.INFO, "Found % map files: %", mapPaths.count, mapPaths);
    log(.INFO, "Found % package files: %", packagePaths.count, packagePaths);
    
    if packagePaths.count != mapPaths.count {
	log(.FATAL, "Failed to find the same number of asset maps and packages");
    }
    
    fusedMap := load_and_merge_asset_maps(gameCode, mapPaths);
    
    map := New(AssetMap);
    
    mapRoot, mapReadSuccess := json_build_tree(fusedMap, "Asset Map Tree");
    if mapReadSuccess != .Success {
	log(.FATAL, "Failed to read the complete asset map with error: %", mapReadSuccess);
    }
    
    for fileValue : mapRoot.values {
	print_color("Processing file: %\n", fileValue.name, color = .HI_CYAN);
	for assetValue : fileValue.values {
	    print_color("\tProcessing asset: %\n", assetValue.name, color = .HI_GREEN);
	    if table_contains(map, assetValue.name) {
		existingItem := table_find_pointer(map, assetValue.name);
		assert(existingItem && existingItem.*);
		log(.ERROR, "Failed to map asset \"%\" from file: \"%\" because there's already an asset with that name from file: \"%\"", assetValue.name, fileValue.name, existingItem.*.file);
	    } else {
		filenameParts := split(fileValue.name, "_");
		type : AssetPackType;
		for enum_names(AssetPackType) {
		    if to_lower_copy(it) == filenameParts[2] {
			type = enum_values_as_enum(AssetPackType)[it_index];
			break;
		    }
		}
		
		item := New(AssetMapItem);
		item.* = .{ copy_string(fileValue.name), type, assetValue.value_int };
		table_add(map, assetValue.name, item);
	    }
	}
    }
    
    return map;
}

///////////////////////////////////////////////////////
// ASSET LOADING //////////////////////////////////////
///////////////////////////////////////////////////////

AssetState :: struct {
    fontAtlases : [..] *FontAtlas;
    map : *AssetMap;

    images : ResourcePool(ImageResource);
    audios : ResourcePool(AudioResource);
    json   : ResourcePool(JSONResource);
}

init_assets :: (assets : *AssetState, gameCode : string) {
    assets.map = load_asset_map(gameCode);

    setup_sentinel :: (sentinel : *$T) {
	sentinel.prev = sentinel;
	sentinel.next = sentinel;
    }
    
    setup_sentinel(*assets.images.sentinel);
    setup_sentinel(*assets.audios.sentinel);
    setup_sentinel(*assets.json.sentinel);
}

Asset :: struct {
    header : PackagedAssetHeader;
    tags : [] string;
    data : *void;
}

get_packaged_assets_path :: () -> string {
    if IS_DEV {
	if OS == .ANDROID {
	    return "bin/";
	} else if OS == .LINUX {
	    return "";
	} else {
	    return "../../../data/packaged/";
	}
    } else {
	if OS == .ANDROID {
	    return "bin/";
	} else {
	    return "./bin/";
	}
    }
}

get_asset :: (type : AssetType, name : string) -> *Asset {
    if type == .Invalid {
	log(.ERROR, "Requested asset type cannot be Invalid");
	return null;
    }
    
    file, header := get_raw_asset_data(loam.assets.map, name);
    if !header {
	return null;
    }
    
    if header.type != type {
	log(.ERROR, "Asset found with name \"%\" does not match requested type % (Got %)", to_string(header.name), type, header.type);
	return null;
    }

    make_asset_and_get_file_data :: (header : *PackagedAssetHeader) -> *Asset, *u8 {
	asset := New(Asset);
	asset.header = header.*;
	asset.tags = make_asset_tags(header);
	
	fileData := (cast(*u8) header) + size_of(PackagedAssetHeader) + header.tagCharCount;

	return asset, fileData;
    }
    
    if #complete type == {
	case .Mesh;  assert(false, "Not Implemented");
	
	case .Image; {
	    asset, assetData := make_asset_and_get_file_data(header);
	    asset.data = get_ktx_texture_from_file_data(header, assetData);

	    free(file.data);
	    if !asset.data {
		free(asset);
		return null;
	    }
	    
	    return asset;
	}

	case .JSON; {
	    asset, assetData := make_asset_and_get_file_data(header);
	    asset.data = alloc(xx header.size);
	    memcpy(asset.data, assetData, xx header.size);

	    free(file.data);
	    if !asset.data {
		free(asset);
		return null;
	    }
	    
	    return asset;
	}

	case .Font; {
	    asset, assetData := make_asset_and_get_file_data(header);
	    asset.data = get_font_from_file_data(header, assetData);
	    
	    free(file.data);
	    if !asset.data {
		free(asset);
		return null;
	    }
	    
	    return asset;
	}
	
	case .Audio; {
	    asset, assetData := make_asset_and_get_file_data(header);
	    asset.data = alloc(xx header.size);
	    memcpy(asset.data, assetData, xx header.size);

	    free(file.data);
	    if !asset.data {
		free(asset);
		return null;
	    }
	    
	    return asset;
	}
	
	case .Video; assert(false, "Not Implemented");
	
	case .Invalid; assert(false, "Invalid should be handled earlier in this function, how did you get here?");
    }
    
    free(file.data);
    return null;
}

get_raw_asset_data :: (map : *AssetMap, name : string) -> fileContents : string, assetInfo : *PackagedAssetHeader {
    found, item := table_find(map, name);
    if !found {
	log(.ERROR, "Failed to find asset \"%\" in the asset map file", name);
	return "", null;
    }

    itemFilename := join(get_packaged_assets_path(), item.file, ".", ASSET_PACK_FILE_EXTENSION);
    rawPackContents, readSuccess := read_file(itemFilename);
    
    packDecompSuccess, packContents := decompress_data(rawPackContents);
    if !packDecompSuccess {
	log(.FATAL, "Failed to decompress asset pack \"%\"", itemFilename);
    }
    free(rawPackContents.data);

    // NOTE: We used to check for a file code, currently that's scrapped but maybe it's a good idea to bring back? Do we care????
    
    // Check we're getting a valid space in the file memory
    if item.offset > packContents.count ||
       item.offset + size_of(PackagedAssetHeader) > packContents.count {
	log(.ERROR, "Attempted to access invalid memory for asset header");
	free(packContents.data);
	return "", null;
    }

    header := cast(*PackagedAssetHeader) (packContents.data + item.offset);
    assetDataOffset := item.offset + size_of(PackagedAssetHeader) + header.tagCharCount;
    
    if assetDataOffset + cast(s64) header.size > packContents.count {
	log(.ERROR, "Attempted to access invalid memory for asset data");
	free(packContents.data);
	return "", null;
    }
    
    return packContents, header;
}

get_ktx_texture_from_file_data :: (header : *PackagedAssetHeader, fileData : *void) -> *ktxTexture2 {
    texture : *ktxTexture2;
    createResult := ktxTexture2_CreateFromMemory(cast(*u8) fileData, header.size, .LOAD_IMAGE_DATA_BIT, *texture);
    if createResult != .SUCCESS {
	log(.ERROR, "Failed to create ktx texture for \"%\" with error: %", to_string(header.name), createResult);
	ktxTexture2_Destroy(texture);
	return null;
    }
    
    return texture;
}

get_font_from_file_data :: (header : *PackagedAssetHeader, fileData : *void) -> *FontData {
    fontData := New(FontData);
    fontData.data = NewArray(xx header.size, u8);
    memcpy(fontData.data.data, fileData, xx header.size);
    
    error := FT_Init_FreeType(*fontData.lib);
    if error {
	log(.ERROR, "Failed to initialise FreeType for font \"%\": %", to_string(header.name), FT_Error_String(error));
	free(fontData);
	return null;
    }

    error = FT_New_Memory_Face(fontData.lib, fontData.data.data, cast(s32) fontData.data.count, 0, *fontData.face);
    if error {
	log(.ERROR, "Failed to initialise Face for font \"%\": %", to_string(header.name), FT_Error_String(error));
	FT_Done_FreeType(fontData.lib);
	free(fontData);
	return null;
    }

    return fontData;
}

make_asset_tags :: (header : *PackagedAssetHeader) -> [] string {
    tagString := string.{ header.tagCharCount, (cast(*u8) header) + size_of(PackagedAssetHeader) };
    unallocedTags := split(tagString, #char "\0");

    tags : [..] string;
    for unallocedTags {
	array_add(*tags, copy_string(it));
    }

    return tags;
}

/////////////////////////////////////////////////////
// COMPRESSION //////////////////////////////////////
/////////////////////////////////////////////////////

compress_data :: (data : string) -> bool, string {
    maxCompressedSize := LZ4_compressBound(cast(s32) data.count);
    compressedRawData := alloc(maxCompressedSize);
    bytesWritten := LZ4_compress_default(data.data, compressedRawData, cast(s32) data.count, maxCompressedSize);
    if bytesWritten == 0 {
	log(.ERROR, "compress_data failed!");
	return false, .{};
    }
    
    log(.DEV, "Compressed data from % to %", to_size_string(cast(u64) data.count), to_size_string(cast(u64) bytesWritten));
    
    compData := alloc_string(bytesWritten);
    memcpy(compData.data, compressedRawData, bytesWritten);
    free(compressedRawData);
    
    return true, compData;
}

decompress_data :: (data : string) -> bool, string {
    decompressedRawData := alloc(MAX_ASSET_PACKAGE_SIZE);
    bytesWritten := LZ4_decompress_safe(data.data, decompressedRawData, cast(s32) data.count, cast(s32) MAX_ASSET_PACKAGE_SIZE);
    if bytesWritten <= 0 {
	log(.ERROR, "decompress_data failed with: %", bytesWritten);
	return false, .{};
    }
    
    log(.DEV, "Decompressed data from % to %", to_size_string(cast(u64) data.count), to_size_string(cast(u64) bytesWritten));
    
    decompData := alloc_string(bytesWritten);
    memcpy(decompData.data, decompressedRawData, bytesWritten);
    free(decompressedRawData);
    
    return true, decompData;
}


