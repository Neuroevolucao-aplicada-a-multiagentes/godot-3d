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

# Posicoes de nascimento dos agentes. A coleta inicial e sorteada entre as
# vagas livres proximas, igual a qualquer ciclo seguinte.
const SPAWNS: Array = [
	Vector2(15.1, -45.0),
	Vector2(24.9, -71.0),
	Vector2(15.1, -60.0),
	Vector2(24.9, -45.0),
	Vector2(15.1, -52.0),
]

# --- Vagas de coleta --------------------------------------------------------
# Cada vaga tem dois pontos distintos, e a separacao entre eles e deliberada:
#
#   visual: na face da prateleira, onde a carga fica visivel.
#   alvo:   no centro do corredor, que e o ponto que o agente persegue.
#
# Aproximar o alvo da prateleira reproduz o modo de falha medido no ambiente
# 2D: com folga de 2.6 u as colisoes por minuto foram 366 e as entregas 79;
# com 4.0 u, 210 e 107. O centro do corredor da 3.9 u de folga, que e o limite.
const FOLGA_VISUAL := 0.35   # afasta a esfera da face para nao haver z-fight
const ALTURA_VISUAL := 1.2   # altura de prateleira, mais legivel que o chao

# [centro do corredor, face da prateleira adjacente]
const FACES: Array = [
	[15.1, 11.2], [15.1, 19.0],
	[24.9, 21.0], [24.9, 28.8],
]

# Posicoes em z dentro dos trechos de prateleira, concentradas perto das
# extremidades e dos corredores transversais. O miolo do trecho longo do sul
# fica de fora: e onde a politica reativa nao completa o ciclo.
const ZS_VAGAS: Array = [
	-25.5, -28.0, -38.0, -41.0,
	-55.0, -58.0, -63.0, -66.0,
	-80.0, -83.0,
]

const SEMENTE := 7
const DISTANCIA_MAX_VAGA := 40.0

var _vagas: Array = []
var _vaga_do_agente: Dictionary = {}
var _visual_do_agente: Dictionary = {}
var _ocupadas: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _montar_vagas() -> void:
	_vagas.clear()
	for par in FACES:
		var centro: float = par[0]
		var face: float = par[1]
		var lado: float = signf(centro - face)   # para que lado fica o corredor
		for z in ZS_VAGAS:
			_vagas.append({
				"visual": Vector3(face + lado * FOLGA_VISUAL, ALTURA_VISUAL, z),
				"alvo": Vector3(centro, 0.5, z),
			})


## Sorteia uma vaga livre, preferindo as proximas de "perto" para que o
## percurso fique na faixa em que a politica opera.
func _sortear_vaga(perto: Vector3, excluir: int) -> int:
	var candidatas: Array[int] = []
	for i in _vagas.size():
		if i == excluir or _ocupadas.has(i):
			continue
		var d: float = (_vagas[i]["alvo"] as Vector3).distance_to(perto)
		if d <= DISTANCIA_MAX_VAGA:
			candidatas.append(i)
	if candidatas.is_empty():
		for i in _vagas.size():
			if i != excluir and not _ocupadas.has(i):
				candidatas.append(i)
	if candidatas.is_empty():
		return excluir
	return candidatas[_rng.randi_range(0, candidatas.size() - 1)]


func _atribuir(agente: AgenteIA, perto: Vector3) -> void:
	var antiga: int = _vaga_do_agente.get(agente, -1)
	if antiga >= 0:
		_ocupadas.erase(antiga)
	var nova := _sortear_vaga(perto, antiga)
	_ocupadas[nova] = true
	_vaga_do_agente[agente] = nova

	var marker: Marker3D = _visual_do_agente[agente]
	marker.global_position = _vagas[nova]["visual"]
	marker.visible = true
	agente.mover_alvo_pacote(_vagas[nova]["alvo"])


func _ao_coletar(agente: AgenteIA) -> void:
	# A carga saiu da prateleira: apaga o marcador ate a proxima atribuicao.
	(_visual_do_agente[agente] as Marker3D).visible = false


func _ao_entregar(agente: AgenteIA) -> void:
	_atribuir(agente, agente.global_position)


func _ready() -> void:
	var cena_npc := load("res://npc.tscn") as PackedScene
	if cena_npc == null:
		push_error("GerenciadorSimulacao: falha ao carregar npc.tscn")
		return

	_rng.seed = SEMENTE
	_montar_vagas()

	# Marcador unico da entrega, compartilhado por todos os agentes. Maior que
	# os de coleta para ficar legivel a distancia.
	var entrega := _criar_marker(ENTREGA, 0.7)

	for i in SPAWNS.size():
		var spawn: Vector2 = SPAWNS[i]

		var npc: Node3D = cena_npc.instantiate()
		add_child(npc)
		npc.name = "NPC_%d" % i
		npc.global_position = Vector3(spawn.x, 0.5, spawn.y)

		var corpo := npc.get_node("ProtoController") as AgenteIA

		# Alvo de navegacao: Marker3D sem malha, invisivel em cena.
		var alvo := Marker3D.new()
		add_child(alvo)
		corpo.configurar(alvo, entrega)
		corpo.mostrar_debug = (i == 0)

		_visual_do_agente[corpo] = _criar_marker(Vector3.ZERO, 0.4)
		corpo.coletou.connect(_ao_coletar.bind(corpo))
		corpo.entregou.connect(_ao_entregar.bind(corpo))
		_atribuir(corpo, Vector3(spawn.x, 0.5, spawn.y))

	print("[vagas] %d vagas de coleta em %d faces x %d posicoes"
		% [_vagas.size(), FACES.size(), ZS_VAGAS.size()])

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
