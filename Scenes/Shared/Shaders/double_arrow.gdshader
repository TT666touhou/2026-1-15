shader_type canvas_item;

// 是否啟用雙箭頭效果（UNLIMITED 時為 true）
uniform bool is_unlimited = false;

// 偏移方向（標準化的方向向量，用於計算複製箭頭的位置）
uniform vec2 offset_direction = vec2(0.0, 0.0);

// 偏移距離（相對於紋理大小的比例，例如 0.15 表示偏移 15% 的紋理大小）
uniform float offset_distance : hint_range(0.0, 1.0) = 0.15;

// 複製箭頭的透明度（可選，用於視覺區分）
uniform float duplicate_alpha : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec4 final_color;
	
	if (is_unlimited && length(offset_direction) > 0.0) {
		// 對稱偏移，使兩個箭頭都相對於中心移動，確保大小一致且居中
		vec2 half_offset = offset_direction * offset_distance * 0.5;
		
		vec2 uv1 = UV + half_offset;
		vec2 uv2 = UV - half_offset;
		
		vec4 color1 = vec4(0.0);
		if (uv1.x >= 0.0 && uv1.x <= 1.0 && uv1.y >= 0.0 && uv1.y <= 1.0) {
			color1 = texture(TEXTURE, uv1);
		}
		
		vec4 color2 = vec4(0.0);
		if (uv2.x >= 0.0 && uv2.x <= 1.0 && uv2.y >= 0.0 && uv2.y <= 1.0) {
			color2 = texture(TEXTURE, uv2);
		}
		
		// 混合兩個箭頭，color2 疊加在 color1 之上
		final_color = mix(color1, color2, color2.a * duplicate_alpha);
	} else {
		final_color = texture(TEXTURE, UV);
	}
	
	// 乘以 COLOR 以支援 Modulate (透明度與顏色)
	COLOR = final_color * COLOR;
}
