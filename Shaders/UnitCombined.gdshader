shader_type canvas_item;

uniform float health_percent : hint_range(0.0, 1.0) = 1.0;
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float crack_scale : hint_range(0.1, 5.0) = 0.5;

// 新增：用來傳遞固定座標的變數
varying vec2 local_pos;

// 偽隨機函式
vec2 hash22(vec2 p) {
    p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
    return fract(sin(p) * 43758.5453123);
}

// 基礎 Voronoi 距離算法
float get_voronoi(vec2 p) {
    vec2 n = floor(p);
    vec2 f = fract(p);
    float m = 8.0;
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            vec2 g = vec2(float(i), float(j));
            vec2 o = hash22(n + g);
            vec2 r = g + o - f;
            float d = dot(r, r);
            if (d < m) m = d;
        }
    }
    return sqrt(m);
}

// 新增頂點處理函式
void vertex() {
    // 記錄原始的頂點位置，這在不同 Frame 之間是固定的
    local_pos = VERTEX;
}

void fragment() {
    vec4 tex_color = texture(TEXTURE, UV);
    if (tex_color.a < 0.01) discard;

    // --- 1. 裂痕 (Voronoi) 邏輯 ---
    float damage = 1.0 - health_percent;
    
    // 使用 floor(local_pos) 確保裂痕座標對齊像素網格，恢復像素感
    float v = get_voronoi(floor(local_pos) * crack_scale);
    
    bool is_crack = false;
    // 根據血量百分比決定裂痕階段 (25, 50, 75%)
    if (damage >= 0.75) { // 血量 < 25%
        if (v > 0.4) is_crack = true;
    } else if (damage >= 0.50) { // 血量 < 50%
        if (v > 0.6) is_crack = true;
    } else if (damage >= 0.25) { // 血量 < 75%
        if (v > 0.8) is_crack = true;
    }

    vec3 base_rgb = tex_color.rgb;
    if (is_crack) {
        // 裂痕顏色：大幅度調暗原始顏色
        base_rgb *= 0.35; 
    }

    // --- 2. 閃爍 (Flash) 邏輯 ---
    // 在裂痕效果之上套用閃爍
    vec3 final_rgb = mix(base_rgb, flash_color.rgb, flash_amount);

    COLOR = vec4(final_rgb, tex_color.a);
}
