extends Node

@export_group("Settings")
@export_range(1, 1000) var _update_frequency: int = 60

@export var _auto_start: bool
@export var _data_texture: Texture2D

@export_group("Requirements")
@export_file("*.glsl") var _compute_shader

@export var _renderer: Sprite2D

var _rd: RenderingDevice

var _input_texture: RID
var _output_texture: RID
var _uniform_set: RID
var _shader: RID
var _pipeline: RID

var _bindings: Array[RDUniform] = []

var _input_image: Image
var _output_image: Image
var _render_texture: ImageTexture

var _input_format: RDTextureFormat
var _output_format: RDTextureFormat
var _processing: bool

var _texture_usage = \
	RenderingDevice.TEXTURE_USAGE_STORAGE_BIT + \
	RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT + \
	RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT

var _default_texture_format: RDTextureFormat

# Called when the node enters the scene tree for the first time.
func _ready():
	_default_texture_format = RDTextureFormat.new()
	_default_texture_format.width = 1024
	_default_texture_format.height = 1024
	_default_texture_format.format = RenderingDevice.DATA_FORMAT_R8_UNORM
	_default_texture_format.usage_bits = _texture_usage

	create_and_validate_images()
	setup_compute_shader()

	if not _auto_start:
		return

	start_process_loop()


func _input(event) -> void:
	if not event is InputEventKey:
		return

	var key: InputEventKey = event as InputEventKey
	if key.keycode != KEY_SPACE or not key.pressed:
		return
	if _processing:
		_processing = false
	else:
		start_process_loop()


func _notification(what) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		cleanup_gpu()


func merge_images() -> void:
	var output_width: int = _output_image.get_width()
	var output_height: int = _output_image.get_height()
	var input_width: int = _input_image.get_width()
	var input_height: int = _input_image.get_height()

	var start_x: int = (output_width - input_width) / 2
	var start_y: int = (output_height - input_height) / 2

	for x in input_width:
		for y in input_height:
			var color: Color = _input_image.get_pixel(x, y)
			var dest_x: int = start_x + x
			var dest_y: int = start_y + y

			if dest_x >= 0 and dest_x < output_width and \
			   dest_y >= 0 and dest_y < output_height:
				_output_image.set_pixel(dest_x, dest_y, color)
	_input_image.set_data(1024, 1024, false, Image.FORMAT_L8, _output_image.get_data())


func link_output_texture_to_renderer() -> void:
	var mat: ShaderMaterial = _renderer.material as ShaderMaterial
	_render_texture = ImageTexture.create_from_image(_output_image)
	mat.set_shader_parameter("binaryDataTexture", _render_texture)


func create_and_validate_images() -> void:
	_output_image = Image.create(1024, 1024, false, Image.FORMAT_L8)
	if _data_texture == null:
			var noise: FastNoiseLite = FastNoiseLite.new()
			noise.frequency = 0.1
			var noise_image: Image = noise.get_image(1024, 1024)
			_input_image = noise_image
	else:
		_input_image = _data_texture.get_image()

	merge_images()
	link_output_texture_to_renderer()



func create_rendering_device() -> void:
	_rd = RenderingServer.create_local_rendering_device()


func create_shader() -> void:
	var shader_file: RDShaderFile = load(_compute_shader)
	var spirv: RDShaderSPIRV = shader_file.get_spirv()
	_shader = _rd.shader_create_from_spirv(spirv)


func create_pipeline() -> void:
	_pipeline = _rd.compute_pipeline_create(_shader)


func create_texture_formats() -> void:
	_input_format = _default_texture_format
	_output_format = _default_texture_format


func create_texture_and_uniform(image: Image, format: RDTextureFormat, binding: int) -> RID:
	var view: RDTextureView = RDTextureView.new()
	var data: PackedByteArray = image.get_data() as PackedByteArray
	var texture: RID = _rd.texture_create(format, view, [data])
	var uniform: RDUniform = RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform.binding = binding

	uniform.add_id(texture)
	_bindings.append(uniform)
	return texture


func create_uniforms() -> void:
	_input_texture = create_texture_and_uniform(_input_image, _input_format, 0)
	_output_texture = create_texture_and_uniform(_output_image, _output_format, 1)
	_uniform_set = _rd.uniform_set_create(_bindings, _shader, 0)


func setup_compute_shader() -> void:
	create_rendering_device()
	create_shader()
	create_pipeline()
	create_texture_formats()
	create_uniforms()


func start_process_loop() -> void:
	var frq: int = 1 / _update_frequency
	_processing = true
	while _processing:
		update()
		await get_tree().create_timer(frq).timeout
		render()


func update() -> void:
	if _rd == null:
		return

	var compute_list: int = _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(compute_list, _pipeline)
	_rd.compute_list_bind_uniform_set(compute_list, _uniform_set, 0)
	_rd.compute_list_dispatch(compute_list, 32, 32, 1)
	_rd.compute_list_end()
	_rd.submit()


func render() -> void:
	if _rd == null:
		return

	_rd.sync()
	var bytes: PackedByteArray = _rd.texture_get_data(_output_texture, 0)
	_rd.texture_update(_input_texture, 0, bytes)
	_output_image.set_data(1024, 1024, false, Image.FORMAT_L8, bytes)
	_render_texture.update(_output_image)


func cleanup_gpu() -> void:
	if _rd == null:
		return

	_rd.free_rid(_input_texture)
	_rd.free_rid(_output_texture)
	_rd.free_rid(_uniform_set)
	_rd.free_rid(_pipeline)
	_rd.free_rid(_shader)
	_rd.free()
	_rd = null
