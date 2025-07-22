/*
Project: Loam
File: vk/text.jai
Author: Brock Salmon
Created: 25JUN2025
*/

FontData :: struct {
    lib : FT_Library;
    face : FT_Face;
    data : [] u8;
}

Text :: struct {
    str : string;
    font : *FontData;
    size : u32;

    using transform : Transform;
    using renderable : Renderable;
}

TemporaryGlyph :: struct {
    width, height : u32;
    bearingX, bearingY, advance : s32;
}

build_text_buffers :: (info : *Text) -> [] Vertex, *void, *AllocatedImageInfo {
    // TODO: Handle text colour codes
    // TODO: Handle escape sequences
    
    // Create Data for string texture
    ftError := FT_Set_Pixel_Sizes(info.font.face, 0, info.size);
    if ftError then log(.ERROR, tprint("Failed to set FreeType pixel sizes: %", FT_Error_String(ftError)));

    maxHeight, baseline : s32;
    textureWidth, textureHeight : s32;

    savedGlyphs : [..] TemporaryGlyph;
    previousGlyphIndex : FT_UInt;
    for info.str {
	glyphIndex := FT_Get_Char_Index(info.font.face, it);
	if FT_Load_Glyph(info.font.face, glyphIndex, FT_LOAD_RENDER) then continue;

	glyph := info.font.face.glyph;
	if FT_HAS_KERNING(info.font.face) && previousGlyphIndex && glyphIndex {
	    delta : FT_Vector;
	    if !FT_Get_Kerning(info.font.face, previousGlyphIndex, glyphIndex, xx FT_Kerning_Mode.DEFAULT, *delta) then textureWidth += cast(s32) (delta.x >> 6);
	}

	textureWidth += cast(s32) (glyph.advance.x >> 6);
	maxHeight = max(maxHeight, glyph.bitmap_top);
	baseline = max(baseline, cast(s32) glyph.bitmap.rows - glyph.bitmap_top);

	array_add(*savedGlyphs, .{ glyph.bitmap.width, glyph.bitmap.rows, glyph.bitmap_left, glyph.bitmap_top, cast(s32) (glyph.advance.x >> 6) });
	
	previousGlyphIndex = glyphIndex;
    }
    
    textureHeight = maxHeight + baseline;

    __mark := get_temporary_storage_mark();
    textureData, rawTextureData := NewArray(textureWidth * textureHeight, u8);
    
    assert(savedGlyphs.count == info.str.count, "Did not get the correct amount of glyphs for this string ( % / % )", savedGlyphs.count, info.str.count);
    cursorX := 0;
    previousGlyphIndex = 0;
    
    for info.str {
	glyphIndex := FT_Get_Char_Index(info.font.face, it);
	if FT_Load_Glyph(info.font.face, glyphIndex, FT_LOAD_RENDER) then continue;

	ftGlyph := info.font.face.glyph;
	if FT_HAS_KERNING(info.font.face) && previousGlyphIndex && glyphIndex {
	    delta : FT_Vector;
	    if !FT_Get_Kerning(info.font.face, previousGlyphIndex, glyphIndex, xx FT_Kerning_Mode.DEFAULT, *delta) then cursorX += delta.x >> 6;
	}

	glyph := *savedGlyphs[it_index];
	if it != #char " " {
	    for y : 0 .. glyph.height-1 {
		for x : 0 .. glyph.width-1 {
		    drawX := cursorX + glyph.bearingX + x;
		    drawY := textureHeight - glyph.bearingY + cast(s32) y;
		    if drawX >= 0 && drawX < textureWidth &&
			drawY >= 0 && drawY < textureHeight {
			    textureData[drawY * textureWidth + drawX] = ftGlyph.bitmap.buffer[y * glyph.width + x];
			}
		}
	    }
	}
	
	cursorX += glyph.advance;
	previousGlyphIndex = glyphIndex;
    }
    
    extent := VkExtent2D.{ cast(u32) textureWidth, cast(u32) textureHeight };
    stringTexture := create_vk_image_from_data(textureData.data, extent, .R8_SRGB, .SAMPLED_BIT | .TRANSFER_DST_BIT, bytesPerPixel=1 );
    
    set_temporary_storage_mark(__mark);
    array_reset(*savedGlyphs);
    
    free(rawTextureData);
    
    info.dimensions = extent_to_vector(extent, 0);
    
    // Build info to upload to GPU
    vertices, vertexMemory := NewArray(4, Vertex);
    vertices[0] = .{ position=.{ info.dimensions.x, 0,                 0 }, uv=.{ 1, 1 } };
    vertices[1] = .{ position=.{ info.dimensions.x, info.dimensions.y, 0 }, uv=.{ 1, 0 } };
    vertices[2] = .{ position=.{ 0,                 0,                 0 }, uv=.{ 0, 1 } };
    vertices[3] = .{ position=.{ 0,                 info.dimensions.y, 0 }, uv=.{ 0, 0 } };

    return vertices, vertexMemory, stringTexture;
}

make_text :: (str : string, font : *FontData, size : u32, transform : Transform, colour := DEFAULT_TEXTURE_TINT) -> *Text {
    text := New(Text);
    text.* = .{ str, font, size, transform, .{} };
    text.tint = colour;
    if str.count > 0 {
	text.vertices, text.texture = build_text_buffers(text);
	text.buffers = New(MeshBuffers);

	upload_mesh_command(DEFAULT_PLANE_INDICES, text.vertices, text.buffers);
    }
    return text;
}

update_text :: (text : *Text, str : string) {
    text.str = str;
    if text.texture {
	free(text.vertexMemory);
	destroy_vk_image(text.texture);
    }
    text.vertices, text.vertexMemory, text.texture = build_text_buffers(text);

    if text.buffers {
	destroy_vk_buffer(text.buffers.vertexBuffer);
	free(text.buffers);
    }

    text.buffers = New(MeshBuffers);
    upload_mesh_command(DEFAULT_PLANE_INDICES, text.vertices, text.buffers);
}

