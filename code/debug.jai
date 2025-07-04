/*
Project: Loam
File: debug.jai
Author: Brock Salmon
Created: 22JUN2025
*/

METRIC_UPDATE_RATE :: 0.1;
DebugMetrics :: struct {
    timeSinceLastMetricUpdate : float64;
    
    framesPerSecond : u32;
    msPerFrame : float64;
    ramUsage : u64;
}

update_debug_metrics :: (metrics : *DebugMetrics, deltaTime : float64) {
    metrics.timeSinceLastMetricUpdate += deltaTime;
    if metrics.timeSinceLastMetricUpdate >= METRIC_UPDATE_RATE {
	metrics.framesPerSecond = cast(u32) (1.0 / deltaTime + 1.0);
	metrics.msPerFrame = deltaTime * 1000.0;
	metrics.ramUsage = get_ram_usage();

	metrics.timeSinceLastMetricUpdate -= METRIC_UPDATE_RATE;
    }
}

render_debug_stats :: (loam : *LoamState, metrics : DebugMetrics) {
    #if OS == .ANDROID {
	frameTimeText : = make_text(tprint("% / % (%Hz)", metrics.framesPerSecond, metrics.msPerFrame, refreshRate), loam.defaultFont, 64,
				    make_transform( position = Vector3.{ 10, windowHeight - 10.0, 0 }, scale = make_vector3(0.5), alignment = .Left | .Top ));
	ramUsageText := make_text(to_size_string(metrics.ramUsage), loam.defaultFont, 64,
				  make_transform( position = Vector3.{ 10, windowHeight - 40.0, 0 }, scale = make_vector3(0.5), alignment = .Left | .Top ));
    } else {
	frameTimeText : = make_text(tprint("% / % (%Hz)", metrics.framesPerSecond, metrics.msPerFrame, refreshRate), loam.defaultFont, 32,
				    make_transform( position = Vector3.{ 10, windowHeight - 10.0, 0 }, scale = make_vector3(0.5), alignment = .Left | .Top ));
	ramUsageText := make_text(to_size_string(metrics.ramUsage), loam.defaultFont, 32,
				  make_transform( position = Vector3.{ 10, windowHeight - 30.0, 0 }, scale = make_vector3(0.5), alignment = .Left | .Top ));
    }
    
    draw_ui_text(loam, *frameTimeText);
    draw_ui_text(loam, *ramUsageText);
}
