/*
Project: Loam
File: text.jai
Author: Brock Salmon
Created: 25JUN2025
*/

RenderGlyph :: struct {
    using transform : Transform;
    using renderable : Renderable2D;
}

MAX_TEXT_LENGTH :: 256;
Text :: struct {
    str : string;
    font : *FontAtlas;
    
    glyphs : [..] *RenderGlyph;

    using transform : Transform;
    dimensions : Vector3;
    tint : Vector4;
}

get_string_original_dimensions :: (str : string, text : *Text) -> Vector2 {
    dimensions := Vector2.{};
    for iterate(str) {
	char := it;
	if char == #char " " {
	    dimensions.x += text.font.spaceWidth;
	} else {
	    found, glyph := table_find_new(text.font.glyphs, char);
	    if found {
		dimensions.x += glyph.advance;
	    }
	}
    }
    dimensions.y = text.font.ascender - text.font.descender;
    return dimensions;
}

get_string_dimensions :: (str : string, text : *Text) -> Vector2 {
    return get_string_original_dimensions(str, text) * text.scale.xy;
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

update_text_position :: (text : *Text, newPosition : Vector3) {
    text.dimensions.xy = get_string_dimensions(text.str, text);
    cursorX := newPosition.x - text.dimensions.x * 0.5;
    cursorY := newPosition.y;

    if text.transform.alignment & .Left   then cursorX += text.dimensions.x * 0.5;
    if text.transform.alignment & .Right  then cursorX -= text.dimensions.x * 0.5;
    if text.transform.alignment & .Top    then cursorY -= text.dimensions.y * 0.5;
    if text.transform.alignment & .Bottom then cursorY += text.dimensions.y * 0.5;

    diff := newPosition - text.position;
    for text.glyphs {
	it.position += diff;
    }

    text.position = newPosition;
}

update_text :: (text : *Text) {
    update_text(text, text.str);
}

update_text :: (text : *Text, str : string) {
    // TODO: Add some text formatting tags handling for changing colour mid string?
    // TODO: Handle rotation correctly
    text.str = str;
    for * text.glyphs {
	free(it.*);
	it.* = null;
    }
    array_reset(*text.glyphs);
    
    text.dimensions.xy = get_string_dimensions(str, text);
    cursorX := text.transform.position.x - text.dimensions.x * 0.5;
    cursorY := text.transform.position.y - text.dimensions.y * 0.5;
    
    if text.transform.alignment & .Left   then cursorX += text.dimensions.x * 0.5;
    if text.transform.alignment & .Right  then cursorX -= text.dimensions.x * 0.5;
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
	
	glyph := New(RenderGlyph);
	glyph.transform  = make_transform( position = .{ cursorX, cursorY, text.transform.position.z }, scale = text.transform.scale, alignment = .Left | .Bottom);
	glyph.tint = text.tint;
	glyph.texture = text.font.image;
	glyph.dimensions = fontGlyph.dimensions;
	glyph.uv0 = fontGlyph.uv0;
	glyph.uv1 = fontGlyph.uv1;
	
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

