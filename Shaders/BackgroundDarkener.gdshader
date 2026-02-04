shader_type canvas_item;

// BackgroundDarkener Shader
// 負責將背景地塊層的顏色按照指定的色板降階變暗

// 從 palette.png 提取的顏色序列 (由暗到亮)
const vec3 PALETTE[7] = vec3[](
	vec3(0.094, 0.098, 0.137), // 181923 - 0: 最暗
	vec3(0.220, 0.251, 0.365), // 38405d - 1
	vec3(0.298, 0.329, 0.427), // 4c546d - 2
	vec3(0.435, 0.408, 0.478), // 6f687a - 3
	vec3(0.545, 0.475, 0.514), // 8b7983 - 4
	vec3(0.710, 0.612, 0.565), // b59c90 - 5
	vec3(1.000, 1.000, 1.000)  // ffffff - 6: 最亮
);

void fragment() {
    vec4 tex_color = texture(TEXTURE, UV);
    
    // 如果像素是透明的，直接跳過
    if (tex_color.a < 0.1) {
        COLOR = tex_color;
    } else {
        vec3 current_rgb = tex_color.rgb;
        vec3 final_rgb = current_rgb;
        
        // 尋找當前像素在色板中最接近的顏色
        float min_diff = 10.0;
        int current_idx = -1;
        
        for (int i = 0; i < 7; i++) {
            float diff = distance(current_rgb, PALETTE[i]);
            if (diff < min_diff) {
                min_diff = diff;
                current_idx = i;
            }
        }
        
        // 如果找到了匹配的顏色，且不是最暗的，則降一階
        if (current_idx > 0) {
            final_rgb = PALETTE[current_idx - 1];
        } else if (current_idx == 0) {
            final_rgb = PALETTE[0]; // 已經是最暗了
        }
        
        COLOR = vec4(final_rgb, tex_color.a);
    }
}
