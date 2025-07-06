/*
Project: Loam
File: assets.jai
Author: Brock Salmon
Created: 22MAY2025
*/

MAX_ASSET_FILE_SIZE :: #run MB(256);
ASSET_FILE_CODE :: u8.[#char "L", #char "G", #char "A", #char "F"];
ASSET_DIR_FILE_EXTENSION :: "ld";
ASSET_PACK_FILE_EXTENSION :: "lp";
ASSET_CORE_FILE_EXTENSION :: "lc";

AssetType :: enum u8 {
    Invalid;
    
    Mesh;
    Image;
    Font;
    Lang;
    Audio;
    Video;
}

DirectoryItem :: struct {
    name     : [30] u8   #align 1;
    type     : AssetType #align 1;
    file     : u8        #align 1;
    offset   : u64       #align 1;
    filepath : [128] u8  #align 1;
} #no_padding
#assert(size_of(DirectoryItem) == 168);

DirectoryFile :: struct {
    fileCode : u32 #align 1;
    encryptSeed : u32 #align 1;
    itemCount : s64 #align 1;
} #no_padding
#assert(size_of(DirectoryFile) == 16);

AssetDirectory :: Table(string, DirectoryItem);

pack_file_code :: (fileCode : [4] u8) -> u32 {
    result : u32;
    for fileCode {
	result = result | ((cast(u32) it) << (it_index * 8));
    }
    return result;
}

MAX_ASSET_CACHE_SIZE : u64 : 512;
AssetState :: struct {
    cacheSentinel : Asset;
    cacheSize : u64;

    directory : *AssetDirectory;
}

AssetHeader :: struct {
    name : [30] u8 #align 1;
    
    type : AssetType #align 1;
    version : u8 #align 1;

    size : u64 #align 1;

    union {
	_Mesh :: struct {
	    
	} #no_padding
	Mesh : _Mesh #align 1;
	
	_Image :: struct {
	    width : u32 #align 1;
	    height : u32 #align 1;
	    mipLevels : u32 #align 1;
	} #no_padding
	Image : _Image #align 1;

	_Font :: struct {
	    supportsUnicode : bool;
	    
	} #no_padding
	Font : _Font #align 1;
	
	_Lang :: struct {

	} #no_padding
	Lang : _Lang #align 1;

	_Audio :: struct {

	} #no_padding
	Audio : _Audio #align 1;

	_Video :: struct {
	    
	} #no_padding
	Video : _Video;
    } #no_padding
} #no_padding
#assert(size_of(AssetHeader) == 52);

Asset :: struct {
    header : AssetHeader;

    next : *Asset;
    prev : *Asset;
    
    // NOTE: This is only used in the engine to store processed asset data (image data after ktx processing for example, not the ktx file contents), it is packaged as 0
    data : *void;
}

// NOTE: This also updates the asset to the 'top' of the asset cache
find_asset_in_cache :: (state : *AssetState, asset : *Asset) -> *Asset {
    currentAsset := state.cacheSentinel.next;
    while currentAsset != *state.cacheSentinel {
	if currentAsset == asset {
	    // Update to the front of the queue
	    state.cacheSentinel.next.prev = asset;
	    asset.next = state.cacheSentinel.next;
	    
	    state.cacheSentinel.next = asset;
	    asset.prev = *state.cacheSentinel;
	    
	    return currentAsset;
	}
	
	currentAsset = currentAsset.next;
    }

    return null;
}

find_asset_in_cache :: (state : *AssetState, name : string) -> *Asset {
    currentAsset := state.cacheSentinel.next;
    while currentAsset != *state.cacheSentinel {
	if cast(string) currentAsset.header.name == name {
	    // Update to the front of the queue
	    state.cacheSentinel.next.prev = currentAsset;
	    currentAsset.next = state.cacheSentinel.next;
	    
	    state.cacheSentinel.next = currentAsset;
	    currentAsset.prev = *state.cacheSentinel;
	    
	    return currentAsset;
	}
	
	currentAsset = currentAsset.next;
    }

    return null;
}

asset_cache_add :: (state : *AssetState, asset : *Asset) {
    // If we don't have any space, evict the oldest cached asset
    if state.cacheSize == MAX_ASSET_CACHE_SIZE then asset_cache_evict(state);

    // Add a new asset to the cache
    state.cacheSentinel.next.prev = asset;
    asset.next = state.cacheSentinel.next;
	    
    state.cacheSentinel.next = asset;
    asset.prev = *state.cacheSentinel;
    
    state.cacheSize += 1;
}

asset_cache_evict :: (state : *AssetState, asset : *Asset = null) {
    // TODO: Either destroy the asset here or make a destroy_asset function
    if !asset {
	last := state.cacheSentinel.prev;
	if last == *state.cacheSentinel then return;

	last.prev.next = *state.cacheSentinel;
	state.cacheSentinel.prev = last.prev;

	free(last);
	state.cacheSize -= 1;
    } else {
	// TODO: Find asset to evict
    }
}

get_packaged_assets_path :: () -> string {
    if IS_DEBUG {
	if OS == .ANDROID {
	    return "data/packaged/";
	} else if OS == .LINUX {
	    return "";
	} else {
	    return "C:/work/loam/data/packaged/";
	}
    } else {
	if OS == .ANDROID {
	    return "bin/";
	} else {
	    return "./bin/";
	}
    }
}

get_raw_assets_path :: () -> string {    
    if IS_DEBUG {
	if OS == .WINDOWS {
	    return "C:/work/loam/data/";
	}
    }

    return "";
}

load_asset_directory :: () -> *AssetDirectory {
    #if OS == .ANDROID {
	directoryContents, readSuccess := read_entire_file(context.android_app.activity.assetManager, tprint("%1%2.%3", get_packaged_assets_path(), APP_NAME, ASSET_DIR_FILE_EXTENSION));
	if !readSuccess then log(.FATAL, "Failed to read asset directory file!");
    } else {
	directoryContents, readSuccess := read_entire_file(tprint("%1%2.%3", get_packaged_assets_path(), APP_NAME, ASSET_DIR_FILE_EXTENSION));
	if !readSuccess then log(.FATAL, "Failed to read asset directory file!");
    }
    
    // Check that the loaded file is big enough to have the file header and at least one item
    if directoryContents.count < size_of(DirectoryFile) + size_of(DirectoryItem) {
	log(.FATAL, "Loaded asset directory file isn't large enough to be a valid directory");
    }

    header := cast(*DirectoryFile) directoryContents.data;
    // Check that the loaded file is a valid directory file
    if header.fileCode != pack_file_code(ASSET_FILE_CODE) then log(.FATAL, "File codes do not match, directory file is invalid");

    if header.encryptSeed != 0 {
	// TODO: Unencrypt file (fileCode should never be encrypted)
    }

    // Check now that the size matches the amount of items in the file
    if directoryContents.count < size_of(DirectoryFile) + header.itemCount * size_of(DirectoryItem) {
	log(.FATAL, "Loaded asset directory file item count doesn't match the file size");
    }

    directory := New(AssetDirectory);
    init(directory, header.itemCount);

    index := size_of(DirectoryFile);
    while index < directoryContents.count {
	item := cast(*DirectoryItem) (directoryContents.data + index);
	key := trim(cast(string) item.name, "\0");
	table_add(directory, copy_string(key), item.*);
	log(.INFO, tprint("Added item to asset table: \"%\"", key));
	index += size_of(DirectoryItem);
    }

    free(directoryContents.data);
    log(.SUCCESS, tprint("Loaded Asset Directory with % items found", directory.count));
    return directory;
}

request_asset :: (loam : *LoamState, type : AssetType, assetName : string, core : bool = false) -> *Asset {
    if type == .Invalid {
	log(.ERROR, "Requested asset type cannot be Invalid");
	return null;
    }
    
    // Check if we've already loaded this recently
    assetInCache := find_asset_in_cache(loam.assets, assetName);
    if assetInCache {
	return assetInCache;
    }

    // Otherwise, load the asset and add it to the cache
    assetFile : string;
    assetHeader : *AssetHeader;
    if core {
	assetFile, assetHeader = get_raw_core_asset_data(assetName);
    } else {
	assetFile, assetHeader = get_raw_asset_data(loam.assets.directory, assetName);
    }
    if !assetHeader {
	return null;
    }

    if assetHeader.type != type {
	free(assetFile.data);
	log(.ERROR, tprint("Asset found with name \"%\" does not match requested type % (Got %)", cast(string) assetHeader.name, type, assetHeader.type));
	return null;
    }
    
    if #complete type == {
	case .Mesh;  assert(false, "Not Implemented");
	
	case .Image; {
	    fileData := (cast(*u8) assetHeader) + size_of(AssetHeader);
	    asset := New(Asset);
	    asset.header = assetHeader.*;
	    asset.data = get_ktx_texture_from_file_data(assetHeader, loam.vk.textureFormat, fileData);

	    free(assetFile.data);
	    if !asset.data {
		free(asset);
		return null;
	    }

	    asset_cache_add(loam.assets, asset);
	    
	    return asset;
	}

	case .Font; {
	    fileData := (cast(*u8) assetHeader) + size_of(AssetHeader);
	    asset := New(Asset);
	    asset.header = assetHeader.*;
	    asset.data = get_font_from_file_data(assetHeader, fileData);
	    
	    free(assetFile.data);
	    if !asset.data {
		free(asset);
		return null;
	    }
	    
	    asset_cache_add(loam.assets, asset);
	    
	    return asset;
	}
	
	case .Lang;  assert(false, "Not Implemented");
	case .Audio; assert(false, "Not Implemented");
	case .Video; assert(false, "Not Implemented");
	
	case .Invalid; assert(false, "Invalid should be handled earlier in this function, how did you get here?");
    }
    
    free(assetFile.data);
    return null;
}

get_raw_asset_data :: (directory : *AssetDirectory, assetName : string) -> fileContents : string, assetInfo : *AssetHeader {
    item, found := table_find(directory, assetName);
    if !found {
	log(.ERROR, tprint("Failed to find asset \"%\" in the asset directory file", assetName));
	return "", null;
    }
    
    packName := tprint("%1%2_%.%", get_packaged_assets_path(), APP_NAME, item.file, ASSET_PACK_FILE_EXTENSION);

    #if OS == .ANDROID {
	packContents, readSuccess := read_entire_file(context.android_app.activity.assetManager, packName);
    } else {
	packContents, readSuccess := read_entire_file(packName);
    }

    if !readSuccess {
	log(.FATAL, tprint("Failed to read asset pack file \"%\"!", packName));
	free(packContents.data);   
	return "", null;
    }

    // Check we're getting a valid space in the file memory
    if item.offset > cast(u64) packContents.count ||
       item.offset + size_of(AssetHeader) > cast(u64) packContents.count {
	log(.ERROR, "Attempted to access invalid memory for asset header");
	free(packContents.data);
	return "", null;
    }

    header := cast(*AssetHeader) (packContents.data + item.offset);
    
    if item.offset + size_of(AssetHeader) + header.size > cast(u64) packContents.count {
	log(.ERROR, "Attempted to access invalid memory for asset data");
	free(packContents.data);
	return "", null;
    }
    
    return packContents, header;
}

get_raw_core_asset_data :: (assetName : string) -> fileContents : string, assetInfo : *AssetHeader {
    packName := tprint("%loam_core.%", get_packaged_assets_path(), ASSET_CORE_FILE_EXTENSION);

    #if OS == .ANDROID {
	packContents, readSuccess := read_entire_file(context.android_app.activity.assetManager, packName);
    } else {
	packContents, readSuccess := read_entire_file(packName);
    }

    if !readSuccess {
	log(.FATAL, "Failed to read core asset pack file!");
	free(packContents.data);
	return "", null;
    }

    fileIndex := 0;
    header : *AssetHeader = null;
    while fileIndex < packContents.count {
	header = cast(*AssetHeader) (packContents.data + fileIndex);
	if to_string(header.name.data) == assetName then return packContents, header;

	fileIndex += cast(s64) (size_of(AssetHeader) + header.size);
    }
    
    return packContents, null;;
}

get_ktx_texture_from_file_data :: (header : *AssetHeader, textureFormat : VkFormat, fileData : *void) -> *ktxTexture2 {
    cleanup_from_error :: (logMsg : string) #expand {
	log(.ERROR, logMsg);
	free(`texture);
	`return null;
    }
    
    texture := New(ktxTexture2);
    createResult := ktxTexture2_CreateFromMemory(cast(*u8) fileData, header.size, .LOAD_IMAGE_DATA_BIT | .CHECK_GLTF_BASISU_BIT, *texture);
    if createResult != .SUCCESS then cleanup_from_error("Failed to create ktx texture.");

    if texture.supercompressionScheme != .BASIS_LZ then cleanup_from_error("Loaded ktx texture isn't Basis-U encoded.");

    // Transcode texture to correct format
    transcodeFormat := ktx_transcode_fmt_e.TTF_RGBA32;
    if textureFormat == {
	case .BC7_SRGB_BLOCK;           transcodeFormat = .TTF_BC7_RGBA;
	case .BC3_SRGB_BLOCK;           transcodeFormat = .TTF_BC3_RGBA;
	case .ASTC_4x4_SRGB_BLOCK;      transcodeFormat = .TTF_ASTC_4x4_RGBA;
	case .ETC2_R8G8B8A8_SRGB_BLOCK; transcodeFormat = .TTF_ETC2_RGBA;

	case; log(.WARN, tprint("Suboptimal VkFormat selected: %, transcoding will continue with uncompressed RGBA32", textureFormat));
    }

    error := ktxTexture2_TranscodeBasis(texture, transcodeFormat, 0);
    if error != .SUCCESS || texture.vkFormat == 0 then cleanup_from_error(tprint("Failed to transcode texture: %", error));
    
    return texture;
}

get_font_from_file_data :: (header : *AssetHeader, fileData : *void) -> *FontData {
    fontData := New(FontData);
    fontData.data = NewArray(xx header.size, u8);
    memcpy(fontData.data.data, fileData, xx header.size);
    
    error := FT_Init_FreeType(*fontData.lib);
    if error {
	log(.ERROR, tprint("Failed to initialise FreeType for font \"%\": %", cast(string) header.name, FT_Error_String(error)));
	free(fontData);
	return null;
    }

    error = FT_New_Memory_Face(fontData.lib, fontData.data.data, cast(s32) fontData.data.count, 0, *fontData.face);
    if error {
	log(.ERROR, tprint("Failed to initialise Face for font \"%\": %", cast(string) header.name, FT_Error_String(error)));
	FT_Done_FreeType(fontData.lib);
	free(fontData);
	return null;
    }

    return fontData;
}
