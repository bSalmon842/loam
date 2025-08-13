/*
Project: Loam
File: text.jai
Author: Brock Salmon
Created: 25JUN2025
*/

RenderGlyph :: struct {
    using transform : Transform;
    using renderable : Renderable;
}

Text :: struct {
    str : string;
    font : *FontAtlas;
    
    glyphs : [..] RenderGlyph;

    using transform : Transform;
    dimensions : Vector3;
    tint : Vector4;
}

get_string_dimensions :: (str : string, atlas : *FontAtlas) -> Vector2 {
    dimensions := Vector2.{};
    for iterate(str) {
	char := it;
	found, glyph := table_find_new(atlas.glyphs, char);
	if found {
	    dimensions.x += glyph.advance;
	}
    }
    dimensions.y = atlas.ascender - atlas.descender;
    return dimensions;
}

build_glyph_buffers :: (glyph : *FontAtlas.GlyphInfo) -> [] Vertex, *void {
    vertices, vertexMemory := NewArray(4, Vertex);
    vertices[0] = .{ position=.{ glyph.dimensions.x, 0,                  0 }, uv=.{ glyph.uv1.x, glyph.uv1.y } };
    vertices[1] = .{ position=.{ glyph.dimensions.x, glyph.dimensions.y, 0 }, uv=.{ glyph.uv1.x, glyph.uv0.y } };
    vertices[2] = .{ position=.{ 0,                  0,                  0 }, uv=.{ glyph.uv0.x, glyph.uv1.y } };
    vertices[3] = .{ position=.{ 0,                  glyph.dimensions.y, 0 }, uv=.{ glyph.uv0.x, glyph.uv0.y } };

    return vertices, vertexMemory;
}

make_text :: (str : string, font : string, size : u32, transform : Transform, colour := DEFAULT_TEXTURE_TINT) -> *Text {
    text := New(Text);

    atlasName := get_font_atlas_name(font, size);
    exists, font := table_find_new(loam.fonts, atlasName);
    if !exists {
	log(.ERROR, tprint("Font atlas \"%\" does not exist", atlasName));
    }
    text.font = font;
    text.transform = transform;
    text.tint = colour;

    if str.count > 0 {
	update_text(text, str);
    }
    
    return text;
}

update_text :: (text : *Text, str : string) {
    // TODO: Add some text formatting tags handling for changing colour mid string?
    // TODO: Handle rotation correctly
    
    text.str = str;
    for text.glyphs {
	if it.vertexMemory {
	    free(it.vertexMemory);
	}

	if it.buffers {
	    destroy_vk_buffer(it.buffers.vertexBuffer);
	    free(it.buffers);
	}
    }
    array_reset(*text.glyphs);
    
    text.dimensions.xy = get_string_dimensions(str, text.font) * text.transform.scale.xy;
    cursorX := text.transform.position.x;
    cursorY := text.transform.position.y;

    if text.transform.alignment & .Center then cursorX -= text.dimensions.x * 0.5;
    if text.transform.alignment & .Right  then cursorX -= text.dimensions.x;
    if text.transform.alignment & .Top    then cursorY -= text.dimensions.y * 0.5;
    if text.transform.alignment & .Bottom then cursorY += text.dimensions.y * 0.5;

    for iterate(text.str) {
	char := it;
	if char == #char " " {
	    cursorX += text.font.spaceWidth * text.transform.scale.x;
	    continue;
	}
	
	found, fontGlyph := table_find_new(text.font.glyphs, char);
	if !found {
	    log(.ERROR, tprint("Failed to get glyph for %", character_utf32_to_utf8(char)));
	    continue;
	}
	
	glyph : RenderGlyph;
	glyph.transform  = make_transform( position = .{ cursorX, cursorY, text.transform.position.z }, scale = text.transform.scale);
	glyph.tint = text.tint;
	glyph.texture = text.font.image;
	glyph.vertices, glyph.vertexMemory = build_glyph_buffers(*fontGlyph);
	glyph.buffers = New(MeshBuffers);
	
	upload_mesh_command(DEFAULT_PLANE_INDICES, glyph.vertices, glyph.buffers);
	
	array_add(*text.glyphs, glyph);

	cursorX += cast(float) fontGlyph.advance * text.transform.scale.x;
    }
}

// NOTE: Better UTF8 looping by Lunatoid from the jai discord
UTF8_Iterable_String :: struct {
    s: string;
};

for_expansion :: (iterable_str: UTF8_Iterable_String, body: Code, flags: For_Flags) #expand {
    char_idx : s64 = 0;

    i : s64 = 0;
    while i < iterable_str.s.count {
        char, byte_len, result := character_utf8_to_utf32(*iterable_str.s[i], iterable_str.s.count-i);
        if result != .CONVERSION_OK
            break;

        `it       := char;
        `it_index := char_idx;

        defer {
            char_idx += 1;
            i += byte_len;
        }

        #insert body;

    }
}

iterate :: (s : string) -> UTF8_Iterable_String {
    return UTF8_Iterable_String.{s};
}

