/*
Project: 
File: font.jai
Author: Brock Salmon
Created: 25JUL2025
*/

ATLAS_MAX_SIZE :: 512;

Language :: enum {
    English;
    
    // NOTE: Adds Latin Supplement, Extension A & B
    English_Extended; // TODO: Make sure this actually fits on one atlas
    
    Japanese; // TODO: Good fucking luck fitting kanji on an atlas in any meaningful way, future Brock
}

FontData :: struct {
    lib : FT_Library;
    face : FT_Face;
    data : [] u8;
}

FontAtlas :: struct {
    image : *ImageResource;
    
    GlyphInfo :: struct {
	bearing    : Vector2;
	advance    : s32;
	dimensions : Vector2;
	
	uv0 : Vector2;
	uv1 : Vector2;
    }
    
    glyphs : *Table(u32, GlyphInfo);

    lineSpacing : float;
    ascender    : float;
    descender   : float;
    spaceWidth  : float;
}

CodepointRange :: struct {
    start, end : u32;
}

get_font_atlas_name :: (fontName : string, size : u32) -> string {
    return tprint("atlas_font_%_%", fontName, size);
}

get_codepoint_ranges_for_language :: (language : Language) -> [] CodepointRange {
    if #complete language == {
	case .English; {
	    return .[ .{ 0x0021, 0x007E } ];
	}
	
	case .English_Extended; {
	    return .[ .{ 0x0021, 0x007E },
		      .{ 0x00A1, 0x024F },
		      .{ 0x1E00, 0x1EFF } ];
	}

	case .Japanese; {
	    return .[ .{ 0x3000, 0x303F },
		      .{ 0x3041, 0x3096 },
		      .{ 0x3099, 0x30FF },
		      .{ 0x4E00, 0x9FFF } ];
	}
    }
}

build_font_atlas :: (fontName : string, size : u32, language : Language, core : bool = false) {
    atlasName := get_font_atlas_name(fontName, size);
    exists := table_find_new(loam.fonts, atlasName);
    if exists {
	log(.WARN, tprint("% already exists", atlasName));
    }
    
    fontData := cast(*FontData) get_asset(.Font, fontName, core).data;
    check_ft(FT_Set_Pixel_Sizes(fontData.face, 0, size), "Failed to set Pixel Sizes");
    
    atlas := New(FontAtlas);
    atlas.glyphs = New(Table(u32, FontAtlas.GlyphInfo));
    init(atlas.glyphs);
    atlasBitmap, bitmapMemory := NewArray(ATLAS_MAX_SIZE * ATLAS_MAX_SIZE, u8);
    defer free(bitmapMemory);

    atlas.lineSpacing = fontData.face.size.metrics.height    / 64.0;
    atlas.ascender    = fontData.face.size.metrics.ascender  / 64.0;
    atlas.descender   = fontData.face.size.metrics.descender / 64.0;

    codepointRanges := get_codepoint_ranges_for_language(language);

    cursorX, cursorY : float = 0;
    
    heightForAtlasRow := 0;
    for range : codepointRanges {
	for range.start .. range.end {
	    charError := FT_Load_Char(fontData.face, it, FT_LOAD_RENDER);
	    if charError != 0 {
		intFmt : FormatInt;
		intFmt.value = it;
		intFmt.base = 16;
		intFmt.minimum_digits = 4;
		log(.WARN, tprint("[FREETYPE] Failed to load char for codepoint 0x%: %", intFmt, FT_Error_String(charError)));
	    }

	    glyphBitmap := fontData.face.glyph.bitmap;
	    if cursorX + cast(s64) glyphBitmap.width >= ATLAS_MAX_SIZE {
		cursorX = 0;
		cursorY += heightForAtlasRow + 1;
		heightForAtlasRow = 0;
	    }

	    for row : 0 .. glyphBitmap.rows-1 {
		for col : 0 .. glyphBitmap.width-1 {
		    x := round_to(cursorX, s32) + col;
		    y := round_to(cursorY, s32) + row;
		    atlasBitmap[y * ATLAS_MAX_SIZE + x] = glyphBitmap.buffer[cast(s32) row * glyphBitmap.pitch + cast(s32) col];
		}
	    }

	    glyph : FontAtlas.GlyphInfo;
	    glyph.uv0 = .{ cursorX / cast(float) ATLAS_MAX_SIZE, cursorY / cast(float) ATLAS_MAX_SIZE };
	    glyph.uv1 = .{ (cursorX + cast(float) glyphBitmap.width) / cast(float) ATLAS_MAX_SIZE, (cursorY + cast(float) glyphBitmap.rows) / cast(float) ATLAS_MAX_SIZE };

	    glyph.advance = cast(s32) (fontData.face.glyph.advance.x >> 6);
	    glyph.bearing = .{ cast(float) fontData.face.glyph.bitmap_left, cast(float) fontData.face.glyph.bitmap_top };
	    glyph.dimensions = .{ cast(float) glyphBitmap.width, cast(float) glyphBitmap.rows };

	    if it == #char "A" then atlas.spaceWidth = cast(float) glyphBitmap.width;
	    
	    table_add(atlas.glyphs, it, glyph);

	    cursorX += glyphBitmap.width;
	    if glyphBitmap.rows > heightForAtlasRow {
		heightForAtlasRow = glyphBitmap.rows;
	    }
	}
    }

    atlasImage := create_vk_image_from_data(atlasBitmap.data, .{ ATLAS_MAX_SIZE, ATLAS_MAX_SIZE }, .R8_SRGB, .SAMPLED_BIT | .TRANSFER_DST_BIT, bytesPerPixel=1);
    atlas.image = add_resource(atlasName, atlasImage, core);
    
    table_add(loam.fonts, copy_string(atlasName), atlas);

    log(.SUCCESS, tprint("% successfully created", atlasName));
}

check_ft :: (result : FT_Error, errMsg : string, errType := Log_Type.ERROR, callLoc := #caller_location) {
    if result != 0 {
        log(errType, tprint("[FREETYPE] %: %", errMsg, FT_Error_String(result)), callLoc);
    }
}
