shader_type canvas_item;

// BackgroundDarkener Shader
// 負責將背景地塊層的顏色按照指定的色板降階變暗

// 從 palette.png 提取的顏色序列 (由暗到亮)
const vec3 PALETTE[9] = vec3[](
	vec3(0.102, 0.110, 0.173), // 1a1c2c - 0: 最暗
	vec3(0.114, 0.133, 0.192), // 1d2231 - 1: 第二暗
	vec3(0.200, 0.235, 0.341), // 333c57 - 2: 第三暗
	vec3(0.322, 0.322, 0.400), // 525266 - 3
	vec3(0.553, 0.529, 0.635), // 8d87a2 - 4
	vec3(0.651, 0.627, 0.710), // a6a0b5 - 5
	vec3(0.831, 0.776, 0.757), // d4c6c1 - 6
	vec3(0.831, 0.741, 0.651), // d4bda6 - 7
	vec3(0.831, 0.627, 0.506)  // d4a081 - 8: 最亮
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
        
        for (int i = 0; i < 9; i++) {
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
