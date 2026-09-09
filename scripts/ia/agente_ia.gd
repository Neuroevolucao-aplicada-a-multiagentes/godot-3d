class_name AgenteIA
extends CharacterBody3D

# Area util apos o realinhamento das fileiras: x ~6..34 (28u),
# z ~-98..-24 (74u) -> diagonal ~79u.
#
# As grandezas abaixo nao sao valores livres: sao as proporcoes fixadas em
# docs/contrato_ambiente.md do repo de treino. A rede so opera dentro da
# distribuicao em que foi treinada se a razao com a diagonal for preservada.
const DIAGONAL_MAPA := 79.0
const ALCANCE_RAY := DIAGONAL_MAPA * 0.203        # 220 / 1081 no treino
const VELOCIDADE_AGENTE := DIAGONAL_MAPA * 0.185  # 200 px/s / 1081
const RAIO_COLETA := DIAGONAL_MAPA * 0.0185       # 20 / 1081
const RAIO_ENTREGA := DIAGONAL_MAPA * 0.0324      # 35 / 1081

const NUM_RAYS := 8
const DURACAO_CICLO := 45.0
const CAMINHO_REDE := "res://assets/melhor_rede_fase5.json"
const COR_GLOW := Color(0.2, 0.8, 1.0)
const COR_CARREGANDO := Color(1.0, 0.5, 0.0)

# layer 1 = estaticos (prateleiras, chao), layer 2 = agentes.
# Os agentes precisam colidir entre si E se enxergar nos raycasts: e disso
# que depende a demonstracao de coordenacao descentralizada.
const MASCARA_PERCEPCAO := 1 | 2

# Altura dos raycasts, em espaco local. Precisa coincidir com o centro da
# capsula de colisao (Collider em y=1.275), e nao com a origem do no: esta
# fica em y=-0.7 no mundo, abaixo das prateleiras, e os raios saiam por
# baixo dos obstaculos sem detectar nada.
const ALTURA_SENSOR := 1.275

# --- Camada reativa de desencalhe -------------------------------------------
# NAO faz parte da rede neural. E uma camada de seguranca por fora dela,
# analoga aos gerenciadores de trafego usados em frotas de AMR reais, e
# precisa ser declarada como tal ao apresentar resultados.
#
# Existe porque a rede nao tem politica de recuperacao: no treino,
# max_colisoes_morte eliminava o agente na quarta colisao, entao a evolucao
# selecionou para EVITAR contato, nunca para SAIR dele. Encostado na parede,
# a rede recebe entradas constantes, devolve a mesma saida e fica num ponto
# fixo. Esta camada quebra esse ponto fixo.
const TEMPO_ATE_DESENCALHE := 0.5   # segundos em contato sem avancar
const DURACAO_DESENCALHE := 0.6     # duracao do empurrao lateral
const DESLOCAMENTO_MINIMO := 0.05   # por frame, para considerar que avancou

@export var alvo: Node3D
@export var zona_entrega: Node3D
@export var carregando_item: bool = false
@export var mostrar_debug: bool = false
@export var usar_desencalhe: bool = true

var rede: RedeNeural
var tempo_ciclo: float = 0.0
var itens_entregues: int = 0
var desencalhes: int = 0

var _alvo_pacote: Node3D
var _raycasts: Array[RayCast3D] = []
var _ultimo_heading: float = 0.0
var _mat_glow: StandardMaterial3D
var _pos_anterior := Vector3.ZERO
var _tempo_travado := 0.0
var _tempo_desencalhe := 0.0
var _dir_desencalhe := Vector2.ZERO

func _ready() -> void:
	rede = RedeNeural.new()
	if not rede.carregar(CAMINHO_REDE):
		push_error("AgenteIA [%s]: falha ao carregar rede neural" % name)

	collision_layer = 2
	collision_mask = MASCARA_PERCEPCAO

	for i in NUM_RAYS:
		var ray := RayCast3D.new()
		ray.name = "Ray%d" % i
		ray.enabled = true
		ray.exclude_parent = true
		ray.collision_mask = MASCARA_PERCEPCAO
		ray.position = Vector3(0.0, ALTURA_SENSOR, 0.0)
		ray.target_position = Vector3(ALCANCE_RAY, 0.0, 0.0)
		add_child(ray)
		_raycasts.append(ray)

	_criar_visual_glow()
	_pos_anterior = global_position

func _criar_visual_glow() -> void:
	var esfera := SphereMesh.new()
	esfera.radius = 0.22
	esfera.height = 0.44

	_mat_glow = StandardMaterial3D.new()
	_mat_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_glow.emission_enabled = true
	_mat_glow.emission = COR_GLOW
	_mat_glow.emission_energy_multiplier = 5.0
	_mat_glow.albedo_color = COR_GLOW

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = esfera
	mesh_inst.material_override = _mat_glow
	mesh_inst.position = Vector3(0.0, 2.1, 0.0)
	add_child(mesh_inst)

func configurar(pacote: Node3D, entrega: Node3D) -> void:
	_alvo_pacote = pacote
	zona_entrega = entrega
	alvo = _alvo_pacote

func _physics_process(delta: float) -> void:
	tempo_ciclo += delta

	if not is_on_floor():
		velocity.y -= 9.8 * delta
		# sem movimento horizontal ate pousar — impede drift para dentro das prateleiras
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	# Zera a componente vertical ao pousar. Sem isto, velocity.y mantinha o
	# valor acumulado durante a queda, o corpo alternava entre "no chao" e
	# "no ar" a cada frame, e o ramo acima anulava velocity.x/z -- o agente
	# rodava a rede normalmente mas ficava parado no lugar.
	velocity.y = 0.0

	if rede.w1.is_empty() or alvo == null:
		move_and_slide()
		return

	var inputs := _montar_inputs()
	var output := rede.forward(inputs)

	var vel2d := Vector2(output[0], output[1])
	if vel2d.length() > 1.0:
		vel2d = vel2d.normalized()

	# A camada de desencalhe, quando ativa, sobrepoe a saida da rede por um
	# instante. A rede continua sendo avaliada normalmente (inputs e output
	# acima) para nao criar descontinuidade no ciclo nem no debug.
	if _tempo_desencalhe > 0.0:
		_tempo_desencalhe -= delta
		velocity.x = _dir_desencalhe.x * VELOCIDADE_AGENTE
		velocity.z = _dir_desencalhe.y * VELOCIDADE_AGENTE
	else:
		velocity.x = vel2d.x * VELOCIDADE_AGENTE
		velocity.z = vel2d.y * VELOCIDADE_AGENTE

	move_and_slide()

	if usar_desencalhe:
		_atualizar_desencalhe(delta)
	_pos_anterior = global_position

	_verificar_coleta_entrega()

	if mostrar_debug:
		var adx := alvo.global_position.x - global_position.x
		var adz := alvo.global_position.z - global_position.z
		var raio_min := 1.0
		for r in inputs.slice(8):
			raio_min = minf(raio_min, float(r))
		print("AgenteIA[%s] pos=(%.1f,%.1f,%.1f) dist2d=%.1f |v|=%.1f raio_min=%.2f colis=%d desenc=%d%s carr=%s itens=%d" % [
			name,
			global_position.x, global_position.y, global_position.z,
			sqrt(adx * adx + adz * adz),
			Vector2(velocity.x, velocity.z).length(),
			raio_min,
			get_slide_collision_count(),
			desencalhes,
			"*" if _tempo_desencalhe > 0.0 else " ",
			str(carregando_item),
			itens_entregues
		])

func _atualizar_desencalhe(delta: float) -> void:
	# Considera travado quem esta em contato com algo que nao e o chao e nao
	# conseguiu se deslocar de forma apreciavel neste frame.
	var avancou := _pos_anterior.distance_to(global_position) > DESLOCAMENTO_MINIMO

	if avancou or _tempo_desencalhe > 0.0:
		_tempo_travado = 0.0
		return

	_tempo_travado += delta
	if _tempo_travado < TEMPO_ATE_DESENCALHE:
		return

	_tempo_travado = 0.0
	var direcao := _direcao_de_escape()
	if direcao == Vector2.ZERO:
		return

	_dir_desencalhe = direcao
	_tempo_desencalhe = DURACAO_DESENCALHE
	desencalhes += 1


func _direcao_de_escape() -> Vector2:
	# Normal media das paredes tocadas neste frame, descartando o chao.
	var normal := Vector2.ZERO
	for i in get_slide_collision_count():
		var n: Vector3 = get_slide_collision(i).get_normal()
		if absf(n.y) > 0.7:
			continue
		normal += Vector2(n.x, n.z)

	if normal.length() < 0.01:
		return Vector2.ZERO
	normal = normal.normalized()

	# Desliza ao longo da parede, escolhendo o sentido que aproxima do alvo,
	# em vez de empurrar contra ela. E o comportamento de contorno classico.
	var tangente := Vector2(-normal.y, normal.x)
	if alvo != null:
		var para_alvo := Vector2(
			alvo.global_position.x - global_position.x,
			alvo.global_position.z - global_position.z
		)
		if para_alvo.length() > 0.001 and tangente.dot(para_alvo.normalized()) < 0.0:
			tangente = -tangente

	# Um pouco de normal junto para descolar da parede antes de deslizar.
	return (tangente * 0.8 + normal * 0.6).normalized()


func _verificar_coleta_entrega() -> void:
	if alvo == null or zona_entrega == null or _alvo_pacote == null:
		return
	var dx := alvo.global_position.x - global_position.x
	var dz := alvo.global_position.z - global_position.z
	var raio: float = RAIO_ENTREGA if carregando_item else RAIO_COLETA
	if sqrt(dx * dx + dz * dz) >= raio:
		return
	if not carregando_item:
		carregando_item = true
		alvo = zona_entrega
		if _mat_glow != null:
			_mat_glow.emission = COR_CARREGANDO
			_mat_glow.albedo_color = COR_CARREGANDO
		tempo_ciclo = 0.0
	else:
		carregando_item = false
		itens_entregues += 1
		alvo = _alvo_pacote
		if _mat_glow != null:
			_mat_glow.emission = COR_GLOW
			_mat_glow.albedo_color = COR_GLOW
		tempo_ciclo = 0.0

func _montar_inputs() -> Array:
	var pos := global_position
	var pos_alvo := alvo.global_position

	var dx := pos_alvo.x - pos.x
	var dz := pos_alvo.z - pos.z
	var dist := sqrt(dx * dx + dz * dz)
	var dir_alvo_x := dx / (dist + 1e-6)
	var dir_alvo_z := dz / (dist + 1e-6)

	var dx_ent := dir_alvo_x
	var dz_ent := dir_alvo_z
	if zona_entrega != null:
		var pe := zona_entrega.global_position
		var ddx := pe.x - pos.x
		var ddz := pe.z - pos.z
		var de := sqrt(ddx * ddx + ddz * ddz)
		dx_ent = ddx / (de + 1e-6)
		dz_ent = ddz / (de + 1e-6)

	# velocity guarda a velocidade em unidades de mundo (ate VELOCIDADE_AGENTE).
	# No treino o input 6 e o modulo do vetor JA normalizado, sempre <= 1 --
	# sem dividir pela velocidade, este input ficava saturado em 1.0 sempre.
	var vel_plano := Vector2(velocity.x, velocity.z)
	var vel_mag := minf(vel_plano.length() / VELOCIDADE_AGENTE, 1.0)

	# heading no plano XZ: equivalente ao atan2(vel.y, vel.x) do pygame
	var heading: float
	if vel_plano.length() > 0.01 * VELOCIDADE_AGENTE:
		heading = atan2(velocity.z, velocity.x)
	else:
		heading = atan2(dz, dx) if (dx != 0.0 or dz != 0.0) else 0.0
	_ultimo_heading = heading

	var rays := _get_ray_distances(heading)
	var tempo_norm := minf(tempo_ciclo / DURACAO_CICLO, 1.0)

	var inputs: Array = [
		dir_alvo_x,
		dir_alvo_z,
		dist / DIAGONAL_MAPA,
		1.0 if carregando_item else 0.0,
		dx_ent,
		dz_ent,
		vel_mag,
		tempo_norm,
	]
	inputs.append_array(rays)
	return inputs

func _get_ray_distances(heading: float) -> Array:
	var distancias: Array = []
	for i in NUM_RAYS:
		var ang := heading + (float(i) / NUM_RAYS) * TAU
		var ray: RayCast3D = _raycasts[i]
		ray.target_position = Vector3(cos(ang), 0.0, sin(ang)) * ALCANCE_RAY
		ray.force_raycast_update()
		var d: float
		if ray.is_colliding():
			d = ray.get_collision_point().distance_to(ray.global_position)
		else:
			d = ALCANCE_RAY
		distancias.append(d / ALCANCE_RAY)
	return distancias
