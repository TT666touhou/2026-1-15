shader_type canvas_item;

uniform vec4 fog_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 star_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float speed : hint_range(0.0, 2.0) = 0.5;
uniform float flame_intensity : hint_range(0.0, 1.0) = 0.03;
uniform vec2 pixel_resolution = vec2(320.0, 176.0);

// Star controls
uniform float star_density : hint_range(0.0, 0.2) = 0.015;
uniform float star_drift_speed : hint_range(0.0, 1.0) = 0.02;
uniform float star_flicker_speed : hint_range(0.0, 5.0) = 1.2;

// Mask coordinates (0.0 to 1.0)
uniform float mask_left = 0.329;
uniform float mask_right = 0.92;
uniform float mask_top = 0.06;
uniform float mask_bottom = 0.94;

float noise(vec2 uv) {
    return fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453);
}

float smooth_noise(vec2 uv) {
    vec2 i = floor(uv);
    vec2 f = fract(uv);
    f = f * f * (3.0 - 2.0 * f);
    
    float a = noise(i);
    float b = noise(i + vec2(1.0, 0.0));
    float c = noise(i + vec2(0.0, 1.0));
    float d = noise(i + vec2(1.0, 1.0));
    
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
    // 1. Pixelation: Quantize UV coordinates
    vec2 uv = floor(UV * pixel_resolution) / pixel_resolution;
    
    // 2. Dynamic Flame Noise
    float n1 = smooth_noise(uv * 12.0 + vec2(TIME * speed * 0.3, TIME * speed));
    float n2 = smooth_noise(uv * 18.0 - vec2(TIME * speed * 0.5, TIME * speed * 0.7));
    float combined_noise = (n1 + n2) * 0.5;
    
    // 3. Grid & UI Mask
    float is_in_grid_h = step(mask_left, uv.x) * (1.0 - step(mask_right, uv.x));
    float is_in_grid_v = step(mask_top, uv.y) * (1.0 - step(mask_bottom, uv.y));
    float in_grid = is_in_grid_h * is_in_grid_v;
    
    float in_ui = 1.0 - step(0.25, uv.x);
    
    // Distance to edge for flame "licking"
    float dist_to_left = abs(uv.x - mask_left);
    float dist_to_right = abs(uv.x - mask_right);
    float dist_to_top = abs(uv.y - mask_top);
    float dist_to_bottom = abs(uv.y - mask_bottom);
    
    float min_dist = 1.0;
    if (is_in_grid_v > 0.5) min_dist = min(min_dist, min(dist_to_left, dist_to_right));
    if (is_in_grid_h > 0.5) min_dist = min(min_dist, min(dist_to_top, dist_to_bottom));
    
    if (uv.x < 0.25) min_dist = 0.0;
    else min_dist = min(min_dist, abs(uv.x - 0.25));

    float fog_mask = 1.0;
    if (in_grid > 0.5 || in_ui > 0.5) {
        if (min_dist > combined_noise * flame_intensity) {
            fog_mask = 0.0;
        }
    }
    
    // 4. Floating Pixel Stars logic
    // Drift the stars' UV over time
    vec2 star_uv = uv + vec2(TIME * star_drift_speed, TIME * star_drift_speed * 0.4);
    // Quantize star_uv to pixel grid to avoid subpixel smoothing
    star_uv = floor(star_uv * pixel_resolution) / pixel_resolution;
    
    float star_n = noise(star_uv * 157.0); // High frequency noise for dots
    float star_visible = 0.0;
    
    if (star_n > 1.0 - star_density) {
        // Flickering: pop in and out based on time and star position
        float flicker_threshold = noise(star_uv * 10.0 + floor(TIME * star_flicker_speed));
        star_visible = step(0.6, flicker_threshold);
    }
    
    // 5. Final Output
    vec4 final_color = fog_color;
    // Only show stars in fog area
    if (fog_mask > 0.5 && star_visible > 0.5) {
        final_color = star_color;
    }
    
    COLOR = vec4(final_color.rgb, fog_mask);
}
