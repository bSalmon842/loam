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

frameTimeText : *Text;
ramUsageText  : *Text;
drawCallText  : *Text;

update_debug_metrics :: (loam : *LoamState, metrics : *DebugMetrics, deltaTime : float64) {
    metrics.timeSinceLastMetricUpdate += deltaTime;
    if metrics.timeSinceLastMetricUpdate >= METRIC_UPDATE_RATE {
	metrics.framesPerSecond = cast(u32) (1.0 / deltaTime + 1.0);
	metrics.msPerFrame = deltaTime * 1000.0;
	metrics.ramUsage = get_ram_usage();

	metrics.totalDrawCalls = 0;
	metrics.nonDebugDrawCalls = 0;
	for loam.vk.pipelines {
	    metrics.totalDrawCalls += cast(u32) it.renderCommands.count;
	    if cast(PipelineTypes) it_index != PipelineTypes.UI_Image && cast(PipelineTypes) it_index != PipelineTypes.UI_Text {
		metrics.nonDebugDrawCalls += cast(u32) it.renderCommands.count;
	    }
	}

	metrics.timeSinceLastMetricUpdate -= METRIC_UPDATE_RATE;
    }
}

render_debug_stats :: (loam : *LoamState, metrics : DebugMetrics) {
    frameTimeText.str = tprint("Frame Time: % / % (%Hz)", metrics.framesPerSecond, metrics.msPerFrame, refreshRate);
    ramUsageText.str  = tprint(" RAM Usage: %", to_size_string(metrics.ramUsage));
    drawCallText.str  = tprint("Draw Calls: % (D: %)", metrics.nonDebugDrawCalls, metrics.totalDrawCalls - metrics.nonDebugDrawCalls);
    
    draw_ui_text(loam, frameTimeText);
    draw_ui_text(loam, ramUsageText);
    draw_ui_text(loam, drawCallText);
}
