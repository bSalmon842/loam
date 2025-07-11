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

    totalDrawCalls    : u32;
    nonDebugDrawCalls : u32;
}

frameTimeText : *UI_Element;
ramUsageText  : *UI_Element;
drawCallText  : *UI_Element;

update_debug_metrics :: (loam : *LoamState, metrics : *DebugMetrics) {
    metrics.timeSinceLastMetricUpdate += loam.deltaTime;
    if metrics.timeSinceLastMetricUpdate >= METRIC_UPDATE_RATE {
	metrics.framesPerSecond = cast(u32) (1.0 / loam.deltaTime + 1.0);
	metrics.msPerFrame = loam.deltaTime * 1000.0;
	metrics.ramUsage = get_ram_usage();

	metrics.totalDrawCalls = 0;
	metrics.nonDebugDrawCalls = 0;
	for loam.vk.pipelines {
	    metrics.totalDrawCalls += cast(u32) it.renderCommands.count;
	    if cast(PipelineTypes) it_index != PipelineTypes.UI_Sprite && cast(PipelineTypes) it_index != PipelineTypes.UI_Text {
		metrics.nonDebugDrawCalls += cast(u32) it.renderCommands.count;
	    }
	}

	metrics.timeSinceLastMetricUpdate -= METRIC_UPDATE_RATE;
    }

    change_text(loam, frameTimeText.text, tprint("Frame Time: % / % (%Hz)", metrics.framesPerSecond, metrics.msPerFrame, refreshRate));
    update_region(frameTimeText, get_default_interact_region(frameTimeText.text));
    change_text(loam, ramUsageText.text, tprint(" RAM Usage: %", to_size_string(metrics.ramUsage)));
    update_region(ramUsageText, get_default_interact_region(ramUsageText.text));
    change_text(loam, drawCallText.text, tprint("Draw Calls: % (D: %)", metrics.nonDebugDrawCalls, metrics.totalDrawCalls - metrics.nonDebugDrawCalls));
    update_region(drawCallText, get_default_interact_region(drawCallText.text));
}

render_debug_ui :: (loam : *LoamState, metrics : DebugMetrics) {
    for loam.debugUIElements {
	draw_ui_element(loam, it);
    }
}
