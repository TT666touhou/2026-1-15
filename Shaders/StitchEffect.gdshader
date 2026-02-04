shader_type canvas_item;

uniform vec4 stitch_color : source_color = vec4(0.71, 0.61, 0.56, 1.0);
uniform float inset : hint_range(0.0, 10.0) = 3.0;
uniform float stitch_length : hint_range(1.0, 10.0) = 2.0;
uniform float stitch_gap : hint_range(1.0, 10.0) = 2.0;
uniform vec2 rect_size;

void fragment() {
    vec2 pixel_pos = UV * rect_size;
    
    // 定義邊界範圍 (考慮 inset)
    float left = inset;
    float top = inset;
    float right = rect_size.x - inset;
    float bottom = rect_size.y - inset;
    
    bool is_on_horizontal_stitch = (abs(pixel_pos.y - top) < 0.5 || abs(pixel_pos.y - bottom) < 0.5) && (pixel_pos.x >= left && pixel_pos.x <= right);
    // 只保留右側的垂直縫線，移除左側 (abs(pixel_pos.x - left) < 0.5)
    bool is_on_vertical_stitch = (abs(pixel_pos.x - right) < 0.5) && (pixel_pos.y >= top && pixel_pos.y <= bottom);
    
    if (is_on_horizontal_stitch || is_on_vertical_stitch) {
        float pos = is_on_horizontal_stitch ? pixel_pos.x : pixel_pos.y;
        if (mod(pos, stitch_length + stitch_gap) < stitch_length) {
            COLOR = stitch_color;
        } else {
            discard;
        }
    } else {
        discard;
    }
}
