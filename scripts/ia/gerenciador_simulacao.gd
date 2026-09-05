extends Node3D

const COR_GLOW := Color(0.2, 0.8, 1.0)

# [x_corredor, spawn_z, alvo_z, entrega_z]
#
# Fileiras em x = 10.2 / 20.0 / 29.8 com colisor de 2.0u -> dois corredores
# livres de 7.8u, centrados em 15.1 e 24.9.
#
# Os agentes COMPARTILHAM corredor, e em cada um ha um par percorrendo
# sentidos opostos (0 contra 1, e 3 contra 4). O encontro frontal e o que
# exige coordenacao: em 7.8u cabem dois agentes de 1.2u lado a lado, mas so
# se um deles ceder espaco. E esse comportamento que a fase 6 vai treinar.
const CONF_AGENTES: Array = [
	[15.1, -30.0, -85.0, -32.0],
	[15.1, -90.0, -35.0, -88.0],
	[15.1, -60.0, -95.0, -45.0],
	[24.9, -35.0, -88.0, -37.0],
	[24.9, -88.0, -40.0, -86.0],
]

func _ready() -> void:
	var cena_npc := load("res://npc.tscn") as PackedScene
	if cena_npc == null:
		push_error("GerenciadorSimulacao: falha ao carregar npc.tscn")
		return

	for i in CONF_AGENTES.size():
		var conf: Array = CONF_AGENTES[i]
		var x: float    = conf[0]
		var spawn_z: float   = conf[1]
		var alvo_z: float    = conf[2]
		var entrega_z: float = conf[3]

		var alvo   := _criar_marker(Vector3(x, 0.5, alvo_z),   0.4)
		var entrega := _criar_marker(Vector3(x, 0.5, entrega_z), 0.25)

		var npc: Node3D = cena_npc.instantiate()
		add_child(npc)
		npc.name = "NPC_%d" % i
		npc.global_position = Vector3(x, 0.5, spawn_z)

		var corpo := npc.get_node("ProtoController") as AgenteIA
		corpo.configurar(alvo, entrega)
		corpo.mostrar_debug = (i == 0)

# cria um Marker3D programatico com esfera emissiva e luz
func _criar_marker(pos: Vector3, raio: float) -> Marker3D:
	var marker := Marker3D.new()
	add_child(marker)
	marker.global_position = pos

	var esfera := SphereMesh.new()
	esfera.radius = raio
	esfera.height = raio * 2.0

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = COR_GLOW
	mat.emission_energy_multiplier = 6.0
	mat.albedo_color = COR_GLOW

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = esfera
	mesh_inst.material_override = mat
	marker.add_child(mesh_inst)

	var luz := OmniLight3D.new()
	luz.light_color = COR_GLOW
	luz.light_energy = 2.0
	luz.omni_range = 5.0
	marker.add_child(luz)

	return marker
