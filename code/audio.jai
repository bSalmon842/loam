/*
Project: Loam
File: audio.jai
Author: Brock Salmon
Created: 16SEP2025
*/

play_audio :: (resourceName : string, category : Audio.Sound_Category, repeat := false) {
    audio := get_resource(AudioResource, resourceName);
    stream := Audio.make_stream(audio.audio, remove_audio_callback, category);
    Audio.set_repeating(stream, repeat);
    Audio.start_playing(stream);
    
    array_add(*loam.activeAudio, stream);
}

update_audio :: () {
    Audio.update(cast(float) loam.deltaTime);
}

remove_audio_callback :: (stream : *Audio.Sound_Stream) {
    for loam.activeAudio {
	if it == stream {
	    remove it;
	    break;
	}
    }
}

change_audio_device :: (newDevice : Audio.Output_Device) {
    Audio.sound_player_shutdown();
    loam.config.audioDevice = newDevice;
    if !Audio.sound_player_init(.{ output_device = *loam.config.audioDevice }) then log(.FATAL, tprint("Failed to change audio device to %", newDevice.name));
}

convert_duration_to_minutes :: (duration : float64) -> string {
    if duration < 60.0 {
	return tprint("%", formatFloat(duration, trailing_width = 1, zero_removal = .NO));
    }
    minutes := floor(duration / 60.0);
    return tprint("%:%", cast(u32) minutes, formatFloat(duration - (minutes * 60.0), trailing_width = 1, zero_removal = .NO));
}

