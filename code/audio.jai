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

play_audio :: (resource : *AudioResource, category : Audio.Sound_Category, repeat := false) {
    stream := Audio.make_stream(resource.audio, remove_audio_callback, category);
    Audio.set_repeating(stream, repeat);
    Audio.start_playing(stream);
    
    array_add(*loam.activeAudio, stream);
}

stop_audio :: (resourceName : string) {
    for loam.activeAudio {
	if compare(it.sound_data.resource.name, resourceName) == 0 {
	    Audio.stop_stream_abruptly(it);
	}
    }
}

stop_audio :: (stream : *Audio.Sound_Stream) {
    Audio.stop_stream_abruptly(stream);
}

restart_audio :: (resourceName : string) {
    for loam.activeAudio {
	if compare(it.sound_data.resource.name, resourceName) == 0 {
	    it.play_cursor = 0;
	}
    }
}

restart_audio :: (stream : *Audio.Sound_Stream) {
    stream.play_cursor = 0;
}

play_audio_if_not_playing :: (resourceName : string, category : Audio.Sound_Category, repeat := false) {
    for loam.activeAudio {
	if compare(it.sound_data.resource.name, resourceName) == 0 {
	    return;
	}
    }
    
    audio := get_resource(AudioResource, resourceName);
    stream := Audio.make_stream(audio.audio, remove_audio_callback, category);
    Audio.set_repeating(stream, repeat);
    Audio.start_playing(stream);
    
    array_add(*loam.activeAudio, stream);
}

play_audio_if_not_playing :: (resource : *AudioResource, category : Audio.Sound_Category, repeat := false) {
    for loam.activeAudio {
	if compare(it.sound_data.resource.name, resource.name) == 0 {
	    return;
	}
    }
    
    stream := Audio.make_stream(resource.audio, remove_audio_callback, category);
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

get_audio_device_from_name :: (deviceName : string) -> Audio.Output_Device {
    devices := Audio.get_devices();
    for devices {
	if it.name == deviceName then return it;
    }

    return .{};
}

change_audio_device :: (name : string) {
    newDevice := get_audio_device_from_name(name);
    if newDevice.name.count {
	Audio.sound_player_shutdown();
	loam.audioDevice = newDevice;
	loam.config.audioDeviceName = name;
	if !Audio.sound_player_init(.{ output_device = *loam.audioDevice }) then log(.FATAL, tprint("Failed to change audio device to %", newDevice.name));
    } else {
	log(.ERROR, tprint("Failed to find an audio device with name \"%\"", name));
    }
}

change_audio_device :: (newDevice : Audio.Output_Device) {
    Audio.sound_player_shutdown();
    loam.audioDevice = newDevice;
    loam.config.audioDeviceName = loam.audioDevice.name;
    if !Audio.sound_player_init(.{ output_device = *loam.audioDevice }) then log(.FATAL, tprint("Failed to change audio device to %", newDevice.name));
}

convert_duration_to_minutes :: (duration : float64) -> string {
    if duration < 60.0 {
	return tprint("%", formatFloat(duration, trailing_width = 1, zero_removal = .NO));
    }
    minutes := floor(duration / 60.0);
    return tprint("%:%", cast(u32) minutes, formatFloat(duration - (minutes * 60.0), trailing_width = 1, zero_removal = .NO));
}

