/*
Project: Loam
File: state.jai
Author: Brock Salmon
Created: 19SEP2025
*/

// TODO: Should this be game extensible?
GameplayState :: enum_flags u8 {
    Invalid :: 0x0;
    
    Splash    :: 0x1;
    Main_Menu :: 0x2;
    Loading   :: 0x4;
    Playing   :: 0x8;
    Cutscene  :: 0x10;
    Paused    :: 0x20;

    All       :: 0xFF;
}

transition_state :: (current : GameplayState, new : GameplayState) {
    if loam.gameplayState == current && current != .Invalid && new != .Invalid {
	loam.gameplayState = new;
	if current == .Splash && new != .Splash {
	    Audio.stop_all_sounds_abruptly(0);
	}
    } else {
	stateNames := enum_names(GameplayState);
	log(.ERROR, tprint("Failed to transition from % to %", stateNames[current], stateNames[new]));
    }
}

SECONDS_PER_SPLASH_SCREEN : float64 : 5.0;
SplashScreen :: struct {
    image : *ImageResource;
    audio : *AudioResource;
    clearColour : Vector4;
}

// TODO: We might want a fade to and from each screen and the main menu
handle_splash_screen :: () {
    if loam.gameplayState == .Splash {
	if loam.splashIndex >= loam.splashScreens.count {
	    transition_state(.Splash, .Playing);
	    return;
	}

	splash := loam.splashScreens[loam.splashIndex];
	renderable := Renderable2D.{};
	renderable.texture = splash.image;
	renderable.dimensions = extent_to_vector(splash.image.image.extent);
	transform := make_transform(.{ cast(float) loam.windowWidth, cast(float) loam.windowHeight, 0 } / 2.0);
	add_sprite_render_command(.Sprite, renderable, transform);

	if splash.audio {
	    play_audio_if_not_playing(splash.audio, .MUSIC, false);
	}
	
	loam.splashTimer += loam.deltaTime;
	if loam.splashTimer >= SECONDS_PER_SPLASH_SCREEN {
	    loam.splashTimer - SECONDS_PER_SPLASH_SCREEN;
	    loam.splashIndex += 1;
	}
    }
}

