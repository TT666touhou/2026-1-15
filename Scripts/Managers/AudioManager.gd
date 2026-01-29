extends Node

## AudioManager (Autoload)
## 負責全域音效播放管理，對接 GlobalSettings 的音量控制

# 音效資源預載入
var sounds = {
	"wall_collision": preload("res://Assets/Audio/wood hitting ground 6.wav"),
	"unit_collision": preload("res://Assets/Audio/wood hit 12.wav")
}

# 物件池 (簡單實現)
var _player_pool: Array[AudioStreamPlayer2D] = []
const POOL_SIZE = 16

func _ready() -> void:
	# 初始化物件池
	for i in range(POOL_SIZE):
		var player = AudioStreamPlayer2D.new()
		player.bus = "SFX" # 確保對接 SFX Bus
		add_child(player)
		_player_pool.append(player)

## 播放 2D 空間音效
func play_sfx_2d(sound_name: String, position: Vector2, volume_db: float = 0.0) -> void:
	if not sounds.has(sound_name):
		print("[AudioManager] Sound not found: ", sound_name)
		return
	
	# 從池中找一個沒在播放的播放器
	var player = _get_available_player()
	if player:
		player.stream = sounds[sound_name]
		player.global_position = position
		player.volume_db = volume_db
		player.play()

func _get_available_player() -> AudioStreamPlayer2D:
	for p in _player_pool:
		if not p.playing:
			return p
	
	# 如果池滿了，隨機搶佔一個或不播放 (這裡選擇不播放以保護聽覺)
	return null
