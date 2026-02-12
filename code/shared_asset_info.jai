/*
Project: Loam
File: shared_asset_info.jai
Author: Brock Salmon
Created: 16JAN2026
*/

// NOTE: This file is also used by the 'loam_asset_pipeline'

MAX_ASSET_PACKAGE_SIZE :: 256 * 1024 * 1024;

ASSET_PACK_FILE_EXTENSION :: "lp";
ASSET_MAP_FILE_EXTENSION :: "lm";

AssetName :: [32] u8;

AssetType :: enum u32 {
    Invalid;
    
    Mesh;
    Image;
    JSON;
    Font;
    Audio;
    Video;
}

AssetPackType :: enum {
    Engine;
    Game;
    Mod;
    Expac;
}

PackagedAssetHeader :: struct {
    name : AssetName;
    size : u64;
    type : AssetType;
    
    tagCount : u16;
    tagCharCount : u16;
}

