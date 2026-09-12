extends Node3D

const COR_GLOW := Color(0.2, 0.8, 1.0)

# Fileiras em x = 10.2 / 20.0 / 29.8 com colisor de 2.0u -> dois corredores
# longitudinais livres de 7.8u, centrados em 15.1 e 24.9, cortados por dois
# corredores transversais em z ~ -73 e ~ -48.
#
# ENTREGA e UNICA e fica na saida do armazem, depois do fim das fileiras.
# Todos os agentes convergem para la, o que produz o encontro entre eles -
# exatamente o cenario de coordenacao descentralizada que o trabalho defende.
const ENTREGA := Vector3(20.0, 0.5, -16.0)

# [spawn(x, z), coleta(x, z)]
#
# O alcance do raycast e de 16 u e os trechos de prateleira tem de 15 u a 25 u,
# entao numa corrida longa ao lado de uma fileira o agente nunca enxerga o fim
# da barreira e a politica reativa nao tem como contornar. Percursos acima de
# 55 u nao completavam o ciclo; os daqui ficam entre 10 u e 35 u.
#
# Os pares 0 e 1 coletam dentro dos corredores transversais, onde a travessia
# e em campo aberto. Nenhuma coleta fica ao sul de z -78, entao o trecho mais
# longo de prateleira nao chega a ser percorrido.
const CONF_AGENTES: Array = [
	[Vector2(15.1, -45.0), Vector2(24.9, -47.0)],
	[Vector2(24.9, -71.0), Vector2(15.1, -74.0)],
	[Vector2(15.1, -60.0), Vector2(24.9, -62.0)],
	[Vector2(24.9, -45.0), Vector2(15.1, -78.0)],
	[Vector2(15.1, -52.0), Vector2(24.9, -70.0)],
]

func _ready() -> void:
	var cena_npc := load("res://npc.tscn") as PackedScene
	if cena_npc == null:
		push_error("GerenciadorSimulacao: falha ao carregar npc.tscn")
		return

	# Marcador unico da entrega, compartilhado por todos os agentes. Maior que
	# os de coleta para ficar legivel a distancia.
	var entrega := _criar_marker(ENTREGA, 0.7)

	for i in CONF_AGENTES.size():
		var conf: Array = CONF_AGENTES[i]
		var spawn: Vector2 = conf[0]
		var coleta: Vector2 = conf[1]

		var alvo := _criar_marker(Vector3(coleta.x, 0.5, coleta.y), 0.4)

		var npc: Node3D = cena_npc.instantiate()
		add_child(npc)
		npc.name = "NPC_%d" % i
		npc.global_position = Vector3(spawn.x, 0.5, spawn.y)

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
