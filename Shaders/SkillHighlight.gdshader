shader_type canvas_item;

uniform bool active = false;
uniform vec2 size = vec2(200., 70.);
uniform vec2 center1 = vec2(0.5); // Click ripple center
uniform vec2 center2 = vec2(0.5); // Mouse hover center
uniform float time1 : hint_range(0., 1.) = 0.; // Click ripple progress
uniform float time2 : hint_range(0., 1.) = 0.; // Hover highlight progress
uniform float width1 : hint_range(0., 0.5) = 0.05;
uniform float width2 : hint_range(0., 0.5) = 0.1;
uniform float corner_radius : hint_range(0., 1.) = 0.1;
uniform float glow : hint_range(0., 10.) = 0.;
uniform vec4 color : source_color = vec4(1.);
uniform float pixel_size : hint_range(1.0, 16.0) = 2.0;

// Rounded box distance field (Ported & Pixelated)
float rounded_box(vec2 p, vec2 b, float r) {
    vec2 d = abs(p) - b + r;
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0)) - r;
}

void fragment() {
    if (!active && glow <= 0.01 && time1 >= 0.99 && time2 <= 0.01) {
        discard;
    }

    // --- 1. Pixelation Logic ---
    // Quantize UVs to get that blocky pixel-art look
    vec2 grid_uv = floor(UV * size / pixel_size) / (size / pixel_size);
    float aspect_ratio = size.x / size.y;
    
    vec2 p = grid_uv - vec2(0.5);
    p.x *= aspect_ratio;
    
    // --- 2. Shape Detection ---
    float radius_factor = corner_radius;
    float actual_radius = 0.5 * radius_factor;
    vec2 rect_half_size = vec2(aspect_ratio * 0.5, 0.5);
    float dist = rounded_box(p, rect_half_size, actual_radius);
    
    bool in_shape = dist <= 0.0;
    
    // --- 3. Glow Effect (Pixelated Outer) ---
    float glow_alpha = 0.0;
    if (glow > 0.0) {
        float glow_dist = -dist;
        // Step-based falloff for sharp pixel feel
        float glow_val = clamp(1.0 - (glow_dist / width2), 0.0, 1.0);
        // Quantize glow levels
        glow_val = floor(glow_val * 4.0) / 4.0;
        glow_alpha = glow_val * color.a * glow * 0.5;
        glow_alpha *= step(0.0, glow_dist);
    }

    // --- 4. Ripple & Hover Highlights ---
    // Center 1: Click Ripple
    vec2 c1_p = (grid_uv - center1);
    c1_p.x *= aspect_ratio;
    float d1 = length(c1_p);
    
    // Center 2: Hover Follow
    vec2 c2_p = (grid_uv - center2);
    c2_p.x *= aspect_ratio;
    float d2 = length(c2_p);
    
    float max_radius = max(aspect_ratio, 1.0) * 1.2;
    
    // Ripple Ring (Sharp pixels with fade)
    float ripple_radius = max_radius * time1;
    float ripple_width = 0.15 * (1.0 - time1);
    float ring = step(ripple_radius - ripple_width, d1) - step(ripple_radius, d1);
    float ripple_alpha = ring * (1.0 - time1);
    
    // Hover Circle (Sharp pixels)
    float hover_radius = 0.3 * time2;
    float hover_circle = step(d2, hover_radius);
    
    // --- 5. Combine ---
    vec4 final_color = vec4(0.0);
    
    if (in_shape) {
        float alpha = max(ripple_alpha, hover_circle * 0.4);
        // Pulse effect (Only when active)
        float pulse = (sin(TIME * 5.0) * 0.5 + 0.5) * 0.2 * step(0.1, float(active));
        alpha += pulse;
        
        final_color = vec4(color.rgb, clamp(alpha, 0.0, 1.0));
    } else {
        final_color = vec4(color.rgb, glow_alpha);
    }
    
    COLOR = final_color;
}
