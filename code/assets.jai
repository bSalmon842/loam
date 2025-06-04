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

AssetType :: enum u8 {
    Invalid;
    
    Mesh;
    Image;
    Lang;
    Audio;
    Video;
}

DirectoryItem :: struct {
    name   : [30] u8 #align 1;
    type   : AssetType #align 1;
    file   : u8 #align 1;
    offset : u64 #align 1;
} #no_padding
#assert(size_of(DirectoryItem) == 40);

DirectoryFile :: struct {
    fileCode : u32 #align 1;
    totalAssetCount : s64 #align 1;
    encryptSeed : u32 #align 1;
    itemCount : s64 #align 1;
} #no_padding
#assert(size_of(DirectoryFile) == 24);

pack_file_code :: (fileCode : [4] u8) -> u32 {
    result : u32;
    for fileCode {
	result = result | ((cast(u32) it) << (it_index * 8));
    }
    return result;
}

Asset :: struct {
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
    #assert(size_of(Asset) == 52);

get_packaged_assets_path :: () -> string {
    if IS_DEBUG {
	if OS == .ANDROID {
	    return "";
	} else if OS == .LINUX {
	    return "";
	} else {
	    return "C:/work/loam/data/packaged/";
	}
    } else {
	if OS == .ANDROID {
	    return "";
	} else {
	    return "./bin/";
	}
    }
}

get_asset :: () -> *Asset {

}

