/*
Project: Loam
File: assets.jai
Author: Brock Salmon
Created: 22MAY2025
*/

MAX_ASSET_FILE_SIZE :: #run MB(256);
ASSET_FILE_CODE :: u8.[#char "L", #char "G", #char "A", #char "F"];
DIR_FILE_CODE :: u8.[#char "L", #char "D", #char "I", #char "R"];
CORE_FILE_CODE :: u8.[#char "L", #char "C", #char "A", #char " "];
ASSET_DIR_FILE_EXTENSION :: "ld";
ASSET_PACK_FILE_EXTENSION :: "lp";
ASSET_CORE_FILE_EXTENSION :: "lc";

AssetType :: enum u32 {
    Invalid;
    
    Mesh;
    Image;
    JSON;
    Font;
    Audio;
    Video;
}

DirectoryItem :: struct {
    name     : AssetName #align 1;
    type     : AssetType #align 1;
    file     : u8        #align 1;
    offset   : u64       #align 1;
    filepath : [128] u8  #align 1;
} #no_padding
#assert(size_of(DirectoryItem) == 193);

DirectoryFile :: struct {
    fileCode   : u32 #align 1;
    itemCount  : s64 #align 1;
} #no_padding
#assert(size_of(DirectoryFile) == 12);

AssetDirectory :: Table(string, DirectoryItem);

pack_file_code :: (fileCode : [4] u8) -> u32 {
    result : u32;
    for fileCode {
	result = result | ((cast(u32) it) << (it_index * 8));
    }
    return result;
}

ResourceType :: enum {
    Image;
    Audio;
    JSON;
}

MAX_RESOURCE_POOL_COUNT : u32 : 256;
ResourcePool :: struct (T : Type) {
    sentinel : T;
    count    : u32;
    
    array : [MAX_RESOURCE_POOL_COUNT] *T;
}

ResourceBase :: struct (T : Type) {
    name : string;
    core : bool;
    next : *T;
    prev : *T;

    index : u32;
}

ImageResource :: struct {
    using _res : ResourceBase(#this);
    image : *AllocatedImageInfo;
}

AudioResource :: struct {
    using _res : ResourceBase(#this);
    audio : *Audio.Sound_Data;
}

JSONResource :: struct {
    using _res : ResourceBase(#this);
    json : *JSON_Value;
}

add_resource :: (name : string, resourceContent : *$T, core : bool = false) -> *$R
    #modify {
	     if T == AllocatedImageInfo { R = ImageResource; }
	else if T == Audio.Sound_Data   { R = AudioResource; }
	else if T == JSON_Value         { R = JSONResource; }
	else                            { return false; }
	
	return true;
    } {
    #if T == {
	case AllocatedImageInfo; {
	    if loam.assets.images.count == MAX_RESOURCE_POOL_COUNT {
		log(.FATAL, "Failed to add resource, image resource cache is full");
		return null;
	    }
	    resource := New(ImageResource);
	    resource.name = copy_string(name);
	    resource.core = core;
	    resource.image = resourceContent;
	    
	    resource.prev = loam.assets.images.sentinel.prev;
	    resource.next = *loam.assets.images.sentinel;
	    
	    loam.assets.images.sentinel.prev.next = resource;
	    loam.assets.images.sentinel.prev = resource;
	    loam.assets.images.count += 1;

	    for * loam.assets.images.array {
		if !it.* {
		    it.* = resource;
		    resource.index = cast(u32) it_index;
		    break;
		}
	    }

	    array_add(*vk.bindlessTextureUpdates, resource);
	    
	    return resource;
	}

	case Audio.Sound_Data; {
	    if loam.assets.audios.count == MAX_RESOURCE_POOL_COUNT {
		log(.FATAL, "Failed to add resource, audio resource cache is full");
		return null;
	    }
	    resource := New(AudioResource);
	    resource.name = copy_string(name);
	    resource.core = core;
	    resource.audio = resourceContent;
	    
	    resource.prev = loam.assets.audios.sentinel.prev;
	    resource.next = *loam.assets.audios.sentinel;
	    loam.assets.audios.count += 1;

	    for * loam.assets.audios.array {
		if !it.* {
		    it.* = resource;
		    resource.index = cast(u32) it_index;
		    break;
		}
	    }
	    
	    return resource;
	}

	case JSON_Value; {
	    if loam.assets.json.count == MAX_RESOURCE_POOL_COUNT {
		log(.FATAL, "Failed to add resource, json resource cache is full");
		return null;
	    }
	    resource := New(JSONResource);
	    resource.name = copy_string(name);
	    resource.core = core;

	    if resourceContent.name == "root" then resourceContent.name = copy_string(name);
	    resource.json = resourceContent;

	    resource.prev = loam.assets.json.sentinel.prev;
	    resource.next = *loam.assets.json.sentinel;
	    loam.assets.json.count += 1;

	    for * loam.assets.json.array {
		if !it.* {
		    it.* = resource;
		    resource.index = cast(u32) it_index;
		    break;
		}
	    }

	    return resource;
	}

	case; {
	    log(.FATAL, "Failed to add resource to cache");
	    return null;
	}
    }
}

// TODO: Reimplement when needed
/*
remove_resource :: ($T : Type, name : string, core : bool = false) {
    #if T == {
	case ImageResource; {
	    sentinel := *loam.assets.imageSentinel;
	    resource := loam.assets.imageSentinel.next;

	    while resource != sentinel {
		if compare(resource.name, name) == 0 && resource.core == core {
		    resource.prev.next = resource.next;
		    resource.next.prev = resource.prev;

		    loam.assets.images.array[resource.index] = null;
		    
		    destroy_vk_image(resource.image);
		    free(resource.name.data);
		    resource.* = .{};
		    free(resource);

		    loam.assets.images.count -= 1;
		    
		    return;
		}

		resource = resource.next;
	    }
	}
    }

    log(.WARN, tprint("Failed to find resource to remove: { %, %, % }", T, name, core));
}
*/

find_resource :: ($T : Type, name : string, core : bool = false) -> *T {
    sentinel, resource : *T;
    #if T == {
	case ImageResource; {
	    sentinel = *loam.assets.images.sentinel;
	    resource = loam.assets.images.sentinel.next;
	}

	case AudioResource; {
	    sentinel = *loam.assets.audios.sentinel;
	    resource = loam.assets.audios.sentinel.next;
	}

	case JSONResource; {
	    sentinel = *loam.assets.json.sentinel;
	    resource = loam.assets.json.sentinel.next;
	}
    }

    while resource != sentinel {
	if compare(resource.name, name) == 0 && resource.core == core {
	    return resource;
	}

	resource = resource.next;
    }

    return null;
}

get_resource :: ($T : Type, name : string, core : bool = false) -> *T {
    resource := find_resource(T, name, core);
    if resource then return resource;
    
    #if T == {
	case ImageResource; {
	    asset := get_asset(.Image, name, core);
	    if asset {
		image := create_vk_image_from_ktx(cast(*ktxTexture2) asset.data);
		return add_resource(name, image, core);
	    }

	    if name == ERROR_TEXTURE_NAME then log(.FATAL, "Failed to find error texture in cache");
	    return get_resource(T, ERROR_TEXTURE_NAME, true);
	}

	case AudioResource; {
	    asset := get_asset(.Audio, name, core);
	    if asset {
		data := string.{ xx asset.header.size, cast(*u8) asset.data };
		audio := New(Audio.Sound_Data);
		audio.* = Audio.load_audio_data(name, data);
		return add_resource(name, audio, core);
	    }

	    return null;
	}

	case JSONResource; {
	    asset := get_asset(.JSON, name, core);
	    if asset {
		data := string.{ xx asset.header.size, cast(*u8) asset.data };
		json := json_build_tree(data, name);
		return add_resource(name, json, core);
	    }

	    return null;
	}
    }
}

MAX_ASSET_CACHE_SIZE : u64 : 512;
AssetState :: struct {
    fontAtlases : [..] *FontAtlas;
    directory : *AssetDirectory;

    images : ResourcePool(ImageResource);
    audios : ResourcePool(AudioResource);
    json   : ResourcePool(JSONResource);
}

ASSET_NAME_COUNT :: 52;
AssetName :: [ASSET_NAME_COUNT] u8;

AssetHeader :: struct {
    name : AssetName #align 1;
    type : AssetType #align 1;
    size : u64 #align 1;
} #no_padding
#assert(size_of(AssetHeader) == 64);

Asset :: struct {
    header : AssetHeader;
    
    // NOTE: This is only used in the engine to store processed asset data (image data after ktx processing for example, not the ktx file contents), it is packaged as 0
    data : *void;
}

get_packaged_assets_path :: () -> string {
    if IS_DEV {
	if OS == .ANDROID {
	    return "data/packaged/";
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

get_raw_assets_path :: () -> string {    
    if IS_DEV {
	if OS == .WINDOWS {
	    return "C:/work/bs_modules/loam/data/";
	}
    }

    return "";
}

make_asset_directory_name :: (name : string, type : AssetType) -> string {
    return tprint("%_%", name, type);
}

init_assets :: (assets : *AssetState) {
    assets.directory = load_asset_directory();

    setup_sentinel :: (sentinel : *$T) {
	sentinel.prev = sentinel;
	sentinel.next = sentinel;
    }
    
    setup_sentinel(*assets.images.sentinel);
    setup_sentinel(*assets.audios.sentinel);
    setup_sentinel(*assets.json.sentinel);
}

load_asset_directory :: () -> *AssetDirectory {
    #if OS == .ANDROID {
	file, opened := file_open(tprint("%1%2.%3", get_packaged_assets_path(), APP_NAME, ASSET_DIR_FILE_EXTENSION));
	if !opened {
	    log(.FATAL, "Failed to open asset directory file!");
	}
	rawDirectoryContents, readSuccess := read_entire_file(file);
	if !readSuccess {
	    log(.FATAL, "Failed to read asset directory file!");
	    return null;
	}
    } else {
	rawDirectoryContents, readSuccess := read_entire_file(tprint("%1%2.%3", get_packaged_assets_path(), APP_NAME, ASSET_DIR_FILE_EXTENSION));
	if !readSuccess {
	    log(.FATAL, "Failed to read asset directory file!");
	    return null;
	}
    }

    dirDecompSuccess, directoryContents := decompress_data(rawDirectoryContents);
    if !dirDecompSuccess {
	log(.FATAL, "Failed to decompress directory file");
    }
    free(rawDirectoryContents);

    // Check that the loaded file is big enough to have the file header and at least one item
    if directoryContents.count < size_of(DirectoryFile) + size_of(DirectoryItem) {
	log(.FATAL, "Loaded asset directory file isn't large enough to be a valid directory");
	return null;
    }
    

    header := cast(*DirectoryFile) directoryContents.data;
    // Check that the loaded file is a valid directory file
    if header.fileCode != pack_file_code(DIR_FILE_CODE) {
	log(.FATAL, "Found asset directory file is not a valid Loam directory file!");
	return null;
    }
    
    // Check now that the size matches the amount of items in the file
    expectedDirectorySize := size_of(DirectoryFile) + header.itemCount * size_of(DirectoryItem);
    if directoryContents.count < expectedDirectorySize {
	log(.FATAL, tprint("Loaded asset directory expected size (%) doesn't match the file size (%)", expectedDirectorySize, directoryContents.count));
	return null;
    }

    directory := New(AssetDirectory);
    init(directory, header.itemCount);

    index := size_of(DirectoryFile);
    while index < directoryContents.count {
	item := cast(*DirectoryItem) (directoryContents.data + index);
	key := trim(cast(string) item.name, "\0");
	dirName := make_asset_directory_name(key, item.type);
	table_add(directory, copy_string(dirName), item.*);
	log(.INFO, tprint("Added item to asset table: \"%\"", key));
	index += size_of(DirectoryItem);
    }

    free(directoryContents.data);
    log(.SUCCESS, tprint("Loaded Asset Directory with % items found", directory.count));
    return directory;
}

get_asset :: (type : AssetType, assetName : string, core : bool = false) -> *Asset {
    if type == .Invalid {
	log(.ERROR, "Requested asset type cannot be Invalid");
	return null;
    }
    
    // Otherwise, load the asset and add it to the cache
    assetFile : string;
    assetHeader : *AssetHeader;
    if core {
	assetFile, assetHeader = get_raw_core_asset_data(assetName, type);
    } else {
	assetFile, assetHeader = get_raw_asset_data(loam.assets.directory, assetName, type);
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
	    asset.data = get_ktx_texture_from_file_data(assetHeader, vk.textureFormat, fileData);

	    free(assetFile.data);
	    if !asset.data {
		free(asset);
		return null;
	    }
	    
	    return asset;
	}

	case .JSON; {
	    fileData := (cast(*u8) assetHeader) + size_of(AssetHeader);
	    asset := New(Asset);
	    asset.header = assetHeader.*;
	    asset.data = alloc(xx assetHeader.size);
	    memcpy(asset.data, fileData, xx assetHeader.size);

	    free(assetFile.data);
	    if !asset.data {
		free(asset);
		return null;
	    }
	    
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
	    
	    return asset;
	}
	
	case .Audio; {
	    fileData := (cast(*u8) assetHeader) + size_of(AssetHeader);
	    asset := New(Asset);
	    asset.header = assetHeader.*;
	    asset.data = alloc(xx assetHeader.size);
	    memcpy(asset.data, fileData, xx assetHeader.size);

	    free(assetFile.data);
	    if !asset.data {
		free(asset);
		return null;
	    }
	    
	    return asset;
	}
	
	case .Video; assert(false, "Not Implemented");
	
	case .Invalid; assert(false, "Invalid should be handled earlier in this function, how did you get here?");
    }
    
    free(assetFile.data);
    return null;
}

get_raw_asset_data :: (directory : *AssetDirectory, assetName : string, type : AssetType) -> fileContents : string, assetInfo : *AssetHeader {
    dirName := make_asset_directory_name(assetName, type);
    found, item := table_find(directory, dirName);
    if !found {
	log(.ERROR, tprint("Failed to find asset \"%\" (%) in the asset directory file", assetName, type));
	return "", null;
    }
    
    packName := tprint("%1%2_%.%", get_packaged_assets_path(), APP_NAME, item.file, ASSET_PACK_FILE_EXTENSION);

    #if OS == .ANDROID {
	file, opened := file_open(packName);
	if !opened {
	    log(.FATAL, "Failed to open asset pack file!");
	}
	rawPackContents, readSuccess := read_entire_file(file);
    } else {
	rawPackContents, readSuccess := read_entire_file(packName);
    }
    
    if !readSuccess {
	log(.FATAL, tprint("Failed to read asset pack file \"%\"!", packName));
	free(rawPackContents.data);
	return "", null;
    }
    
    packDecompSuccess, packContents := decompress_data(rawPackContents);
    if !packDecompSuccess {
	log(.FATAL, tprint("Failed to decompress asset pack \"%\"", packName));
    }
    free(rawPackContents.data);
    
    if !begins_with(packContents, cast(string) ASSET_FILE_CODE) {
	log(.FATAL, "Found asset pack file is not a valid Loam asset pack file!");
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

get_raw_core_asset_data :: (assetName : string, type : AssetType) -> fileContents : string, assetInfo : *AssetHeader {
    packName := tprint("%loam_core.%", get_packaged_assets_path(), ASSET_CORE_FILE_EXTENSION);

    #if OS == .ANDROID {
	file, opened := file_open(packName);
	if !opened {
	    log(.FATAL, "Failed to open core asset pack file!");
	}
	rawPackContents, readSuccess := read_entire_file(file);
    } else {
	rawPackContents, readSuccess := read_entire_file(packName);
    }
    
    if !readSuccess {
	log(.FATAL, "Failed to read core asset pack file!");
	free(rawPackContents.data);
	return "", null;
    }

    packDecompSuccess, packContents := decompress_data(rawPackContents);
    if !packDecompSuccess {
	log(.FATAL, "Failed to decompress core asset pack");
    }
    free(rawPackContents.data);
    
    if !begins_with(packContents, cast(string) CORE_FILE_CODE) {
	log(.FATAL, "Found core asset pack file is not a valid Loam core file!");
	free(packContents.data);
	return "", null;
    }

    fileIndex := 0;
    header : *AssetHeader = null;
    while fileIndex < packContents.count {
	header = cast(*AssetHeader) (packContents.data + fileIndex + size_of(u32)); // Add 4 bytes because of the file code
	if to_string(header.name.data) == assetName && header.type == type then return packContents, header;

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
    createResult := ktxTexture2_CreateFromMemory(cast(*u8) fileData, header.size, .LOAD_IMAGE_DATA_BIT, *texture);
    if createResult != .SUCCESS then cleanup_from_error("Failed to create ktx texture.");
    
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

compress_data :: (data : string) -> bool, string {
    maxCompressedSize := LZ4_compressBound(cast(s32) data.count);
    compressedRawData := alloc(maxCompressedSize);
    bytesWritten := LZ4_compress_default(data.data, compressedRawData, cast(s32) data.count, maxCompressedSize);
    if bytesWritten == 0 {
	log(.ERROR, "compress_data failed!");
	return false, .{};
    }
    
    log(.DEV, tprint("Compressed data from % to %", to_size_string(cast(u64) data.count), to_size_string(cast(u64) bytesWritten)));
    
    compData := alloc_string(bytesWritten);
    memcpy(compData.data, compressedRawData, bytesWritten);
    free(compressedRawData);
    
    return true, compData;
}

decompress_data :: (data : string) -> bool, string {
    maxDecompressedSize : s64 = MAX_ASSET_FILE_SIZE;
    decompressedRawData := alloc(maxDecompressedSize);
    bytesWritten := LZ4_decompress_safe(data.data, decompressedRawData, cast(s32) data.count, cast(s32) maxDecompressedSize);
    if bytesWritten <= 0 {
	log(.ERROR, tprint("decompress_data failed with: %", bytesWritten));
	return false, .{};
    }
    
    log(.DEV, tprint("Decompressed data from % to %", to_size_string(cast(u64) data.count), to_size_string(cast(u64) bytesWritten)));
    
    decompData := alloc_string(bytesWritten);
    memcpy(decompData.data, decompressedRawData, bytesWritten);
    free(decompressedRawData);
    
    return true, decompData;
}


