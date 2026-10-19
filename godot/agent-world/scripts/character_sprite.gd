extends AnimatedSprite2D
## Loads an LPC (Liberated Pixel Cup) walk spritesheet directly — no conversion.
## Format: 9 columns × 4 rows, any frame size (auto-detected from texture dims).
## Col 0 = idle/standing pose, cols 1-8 = walk cycle.
## LPC native row order: 0=up, 1=left, 2=down, 3=right.

const COLS := 9
const ROWS := 4
# LPC native row order
const DIRS := ["up", "left", "down", "right"]
const WALK_FPS := 12

## Target display height in pixels (how tall the sprite renders in-world).
## The sprite is scaled so its frame height matches this value.
## Set to 0 to use the raw frame size with no scaling.
@export var display_height: float = 0.0


func load_spritesheet(path: String) -> void:
	var texture: Texture2D = GameState.load_texture(path)
	if not texture:
		push_warning("Could not load sprite: %s" % path)
		return

	# LPC frames are square. Derive frame size from texture HEIGHT only
	# (height is always exactly 4 rows). The texture width may be larger than
	# 9*frame_size if there's empty padding to the right — that's fine, we
	# only read the first 9 cols.
	var frame_h := texture.get_height() / ROWS
	var frame_w := frame_h

	var frames := SpriteFrames.new()

	# Remove default animation
	if frames.has_animation("default"):
		frames.remove_animation("default")

	for dir_i in range(ROWS):
		var dir_name: String = DIRS[dir_i]

		# Walk animation — cols 1-8 (8 frames, looping). Col 0 is the idle pose.
		var walk_name := "walk_" + dir_name
		frames.add_animation(walk_name)
		frames.set_animation_speed(walk_name, WALK_FPS)
		frames.set_animation_loop(walk_name, true)

		for col in range(1, COLS):
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(col * frame_w, dir_i * frame_h, frame_w, frame_h)
			frames.add_frame(walk_name, atlas)

		# Idle animation (column 0 = standing pose)
		var idle_name := "idle_" + dir_name
		frames.add_animation(idle_name)
		frames.set_animation_speed(idle_name, 1)
		frames.set_animation_loop(idle_name, false)

		var idle_atlas := AtlasTexture.new()
		idle_atlas.atlas = texture
		idle_atlas.region = Rect2(0, dir_i * frame_h, frame_w, frame_h)
		frames.add_frame(idle_name, idle_atlas)

	sprite_frames = frames

	# Scale sprite so it displays at target height (keeps proportions)
	if display_height > 0.0 and frame_h > 0:
		var s := display_height / float(frame_h)
		scale = Vector2(s, s)

	play("idle_down")
