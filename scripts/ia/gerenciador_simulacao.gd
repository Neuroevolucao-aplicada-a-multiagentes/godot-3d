extends Node3D

const COR_GLOW := Color(0.2, 0.8, 1.0)
const COR_DOCA := Color(1.0, 0.8, 0.15)

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
	Vector2(24.9, -56.0),
	Vector2(15.1, -74.0),
	Vector2(24.9, -35.0),
]

# Quantos robos entram em cena. Pode ser trocado na linha de comando com
# -- --robos=N, ate o numero de posicoes de nascimento acima.
const ROBOS_PADRAO := 8

# Parada ao coletar, em milissegundos. Com -- --pausa=N.
const PAUSA_COLETA_MS := 450

# --- Vagas de coleta --------------------------------------------------------
# Cada vaga tem dois pontos distintos, e a separacao entre eles e deliberada:
#
#   visual: na face da prateleira, onde a carga fica visivel.
#   alvo:   no centro do corredor, que e o ponto que o agente persegue.
#
# Aproximar o alvo da prateleira reproduz o modo de falha medido no ambiente
# 2D: com folga de 2.6 u as colisoes por minuto foram 366 e as entregas 79;
# com 4.0 u, 210 e 107. O centro do corredor da 3.9 u de folga, que e o limite.
const FOLGA_VISUAL := 0.45   # afasta a caixa da estrutura da prateleira
const ALTURA_VISUAL := 0.23  # metade da altura da caixa: ela fica apoiada no chao

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
# Distancia entre a face da prateleira e o ponto que o robo persegue. O
# padrao, 3.9 u, e o centro do corredor. Com -- --folga_alvo=N, em decimos.
var _folga_alvo := 3.9
var _vaga_do_agente: Dictionary = {}
var _visual_do_agente: Dictionary = {}
var _ocupadas: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _agentes: Array[AgenteIA] = []

# --- Reatribuicao por falta de progresso ------------------------------------
# Camada de distribuicao de tarefas, fora da rede, como num sistema de gestao
# de armazem. Quando a vaga sorteada fica do outro lado de uma fileira, a
# politica reativa pode ficar deslizando encostada nela sem nunca contornar.
# Se o robo passa SEGUNDOS_SEM_PROGRESSO sem se aproximar do alvo, a coleta e
# trocada por uma vaga no corredor em que ele ja esta.
const SEGUNDOS_SEM_PROGRESSO := 8.0
const GANHO_MINIMO := 1.0
var _progresso: Dictionary = {}
var reatribuicoes := 0


func _montar_vagas() -> void:
	_vagas.clear()
	for par in FACES:
		var centro: float = par[0]
		var face: float = par[1]
		var lado: float = signf(centro - face)   # para que lado fica o corredor
		for z in ZS_VAGAS:
			_vagas.append({
				"visual": Vector3(face + lado * FOLGA_VISUAL, ALTURA_VISUAL, z),
				"alvo": Vector3(face + lado * _folga_alvo, 0.5, z),
				"corredor": centro,
			})


## Sorteia uma vaga livre, preferindo as proximas de "perto" para que o
## percurso fique na faixa em que a politica opera.
func _sortear_vaga(perto: Vector3, excluir: int, corredor: float = -1.0) -> int:
	var candidatas: Array[int] = []
	for i in _vagas.size():
		if i == excluir or _ocupadas.has(i):
			continue
		if corredor >= 0.0 and absf(float(_vagas[i]["corredor"]) - corredor) > 0.1:
			continue
		var d: float = (_vagas[i]["alvo"] as Vector3).distance_to(perto)
		if d <= DISTANCIA_MAX_VAGA:
			candidatas.append(i)
	if candidatas.is_empty() and corredor >= 0.0:
		return _sortear_vaga(perto, excluir)
	if candidatas.is_empty():
		for i in _vagas.size():
			if i != excluir and not _ocupadas.has(i):
				candidatas.append(i)
	if candidatas.is_empty():
		return excluir
	return candidatas[_rng.randi_range(0, candidatas.size() - 1)]


func _atribuir(agente: AgenteIA, perto: Vector3, corredor: float = -1.0) -> void:
	var antiga: int = _vaga_do_agente.get(agente, -1)
	if antiga >= 0:
		_ocupadas.erase(antiga)
	var nova := _sortear_vaga(perto, antiga, corredor)
	_ocupadas[nova] = true
	_vaga_do_agente[agente] = nova

	var marker: Marker3D = _visual_do_agente[agente]
	marker.global_position = _vagas[nova]["visual"]
	marker.visible = true
	agente.mover_alvo_pacote(_vagas[nova]["alvo"])


func _ao_coletar(agente: AgenteIA) -> void:
	# A caixa sai da prateleira e voa ate o robo. O marcador some na hora e
	# volta na proxima atribuicao; quem viaja e uma copia temporaria.
	var marker: Marker3D = _visual_do_agente[agente]
	var copia := MeshInstance3D.new()
	var caixa_original := marker.get_child(0) as MeshInstance3D
	copia.mesh = caixa_original.mesh
	copia.material_override = caixa_original.material_override
	add_child(copia)
	copia.global_position = marker.global_position
	marker.visible = false
	_voos.append({"copia": copia, "origem": marker.global_position,
		"agente": agente, "t": 0.0})


func _ao_entregar(agente: AgenteIA) -> void:
	_enviar_para_pilha(agente.posicao_carga())
	_atribuir(agente, agente.global_position)


func _ready() -> void:
	# Direto no DisplayServer: pela Window, o binario de editor acrescentaria
	# "(DEBUG)" ao titulo.
	DisplayServer.window_set_title.call_deferred(
		str(ProjectSettings.get_setting("application/config/name")))

	var cena_npc := load("res://npc.tscn") as PackedScene
	if cena_npc == null:
		push_error("GerenciadorSimulacao: falha ao carregar npc.tscn")
		return

	_rng.seed = _arg_inteiro("semente", SEMENTE)
	_folga_alvo = _arg_inteiro("folga_alvo", 39) / 10.0
	var pausa := _arg_inteiro("pausa", PAUSA_COLETA_MS) / 1000.0
	_montar_vagas()

	# Doca unica de entrega, compartilhada por todos os agentes.
	var entrega := _criar_doca(ENTREGA)

	var n_robos := clampi(_arg_inteiro("robos", ROBOS_PADRAO), 1, SPAWNS.size())
	for i in n_robos:
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
		corpo.pausa_coleta = pausa
		corpo.mostrar_debug = (i == 0) and "--log-agentes" in OS.get_cmdline_user_args()

		_visual_do_agente[corpo] = _criar_caixa_coleta()
		corpo.coletou.connect(_ao_coletar.bind(corpo))
		corpo.entregou.connect(_ao_entregar.bind(corpo))
		_atribuir(corpo, Vector3(spawn.x, 0.5, spawn.y))
		_agentes.append(corpo)

	_criar_hud(n_robos)
	_criar_faixas()

	var segundos := _arg_inteiro("medir", 0)
	if segundos > 0:
		get_tree().create_timer(segundos).timeout.connect(_relatorio_e_sair)

	print("[vagas] %d vagas de coleta em %d faces x %d posicoes"
		% [_vagas.size(), FACES.size(), ZS_VAGAS.size()])

## Caixa de papelao sobre um disco azul, ao pe da prateleira: a proxima coleta
## de um robo. Some quando ele coleta e reaparece na vaga seguinte.
func _criar_caixa_coleta() -> Marker3D:
	var marker := Marker3D.new()
	add_child(marker)

	var malha := BoxMesh.new()
	malha.size = Vector3(0.6, 0.46, 0.6)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.78, 0.6, 0.4)
	mat.emission_enabled = true
	mat.emission = COR_GLOW
	mat.emission_energy_multiplier = 0.1
	var caixa := MeshInstance3D.new()
	caixa.mesh = malha
	caixa.material_override = mat
	marker.add_child(caixa)

	# Disco azul no chao, embaixo da caixa: a sinalizacao de "e aqui".
	var disco_malha := CylinderMesh.new()
	disco_malha.top_radius = 0.7
	disco_malha.bottom_radius = 0.7
	disco_malha.height = 0.02
	var disco_mat := StandardMaterial3D.new()
	disco_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disco_mat.albedo_color = COR_GLOW
	var disco := MeshInstance3D.new()
	disco.mesh = disco_malha
	disco.material_override = disco_mat
	disco.position = Vector3(0.0, 0.015 - ALTURA_VISUAL, 0.0)
	marker.add_child(disco)

	var luz := OmniLight3D.new()
	luz.light_color = COR_GLOW
	luz.light_energy = 0.9
	luz.omni_range = 2.5
	luz.position = Vector3(0.0, 0.6, 0.0)
	marker.add_child(luz)
	return marker


## Doca de entrega: faixa amarela pintada no chao com o nome escrito. O
## Marker3D fica na posicao que os agentes usam como alvo; o resto e visual.
func _criar_doca(pos: Vector3) -> Marker3D:
	var marker := Marker3D.new()
	add_child(marker)
	marker.global_position = pos

	var malha := BoxMesh.new()
	malha.size = Vector3(5.2, 0.02, 3.2)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.7, 0.12)
	mat.roughness = 0.85
	mat.emission_enabled = true
	mat.emission = COR_DOCA
	mat.emission_energy_multiplier = 0.08
	var piso := MeshInstance3D.new()
	piso.mesh = malha
	piso.material_override = mat
	# Assenta no chao (y = 0) e recua da parede norte, que fica em z -14.7.
	piso.position = Vector3(0.0, 0.01 - pos.y, -0.4)
	marker.add_child(piso)

	var texto := Label3D.new()
	texto.text = "ENTREGA"
	texto.font_size = 110
	texto.pixel_size = 0.01
	texto.modulate = Color(0.12, 0.12, 0.12)
	texto.outline_size = 0
	# Deitado no chao, legivel por quem olha a doca de dentro do galpao.
	texto.transform = Transform3D(
		Basis(Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)),
		Vector3(0.0, 0.03 - pos.y, -0.4))
	marker.add_child(texto)

	var luz := OmniLight3D.new()
	luz.light_color = Color(1.0, 0.9, 0.6)
	luz.light_energy = 1.2
	luz.omni_range = 7.0
	luz.position = Vector3(0.0, 3.0, -0.4)
	marker.add_child(luz)
	return marker


# --- Painel na tela ----------------------------------------------------------
var _hud: CanvasLayer
var _hud_entregas: Label
var _hud_ritmo: Label
var _hud_tempo: Label
var _tempo_decorrido := 0.0
var _voos: Array = []
const DURACAO_VOO := 0.45


func _criar_hud(n_robos: int) -> void:
	_hud = CanvasLayer.new()
	add_child(_hud)

	var painel := PanelContainer.new()
	var estilo := StyleBoxFlat.new()
	estilo.bg_color = Color(0.05, 0.07, 0.09, 0.8)
	estilo.set_corner_radius_all(6)
	estilo.content_margin_left = 20
	estilo.content_margin_right = 20
	estilo.content_margin_top = 16
	estilo.content_margin_bottom = 16
	painel.add_theme_stylebox_override("panel", estilo)
	painel.position = Vector2(24, 24)
	_hud.add_child(painel)

	var coluna := VBoxContainer.new()
	coluna.add_theme_constant_override("separation", 6)
	painel.add_child(coluna)

	_rotulo(coluna, "Neuroevolução em Armazém", 22, Color(1, 1, 1))
	_rotulo(coluna, "Cada robô decide sozinho, com uma rede neural\nde 1.106 parâmetros evoluída por algoritmo genético", 14, Color(0.68, 0.76, 0.8))
	coluna.add_child(HSeparator.new())
	_hud_entregas = _rotulo(coluna, "0 entregas", 34, COR_DOCA)
	_hud_ritmo = _rotulo(coluna, "", 16, Color(0.9, 0.92, 0.94))
	_rotulo(coluna, "%d robôs, sem comunicação entre si" % n_robos, 16, Color(0.9, 0.92, 0.94))
	_hud_tempo = _rotulo(coluna, "", 16, Color(0.9, 0.92, 0.94))
	coluna.add_child(HSeparator.new())
	_legenda(coluna, Color(0.45, 0.85, 1.0), "Caixa sobre disco azul: próxima coleta")
	_legenda(coluna, Color(0.78, 0.6, 0.4), "Robô com caixa: levando para a doca")
	_legenda(coluna, COR_DOCA, "Faixa amarela: doca de entrega")
	_rotulo(coluna, "C câmera automática  ·  H oculta o painel  ·  F11 tela cheia", 12, Color(0.55, 0.6, 0.64))


func _rotulo(pai: Control, texto: String, tamanho: int, cor: Color) -> Label:
	var l := Label.new()
	l.text = texto
	l.add_theme_font_size_override("font_size", tamanho)
	l.add_theme_color_override("font_color", cor)
	pai.add_child(l)
	return l


func _legenda(pai: Control, cor: Color, texto: String) -> void:
	var linha := HBoxContainer.new()
	linha.add_theme_constant_override("separation", 10)
	var amostra := ColorRect.new()
	amostra.color = cor
	amostra.custom_minimum_size = Vector2(14, 14)
	amostra.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	linha.add_child(amostra)
	_rotulo(linha, texto, 15, Color(0.9, 0.92, 0.94))
	pai.add_child(linha)


func _process(delta: float) -> void:
	_animar_voos(delta)
	_animar_entregas(delta)
	_animar_expedicoes(delta)
	if _camera_auto:
		_mover_camera(delta)
	if _hud == null:
		return
	_tempo_decorrido += delta
	var total := 0
	for a in _agentes:
		total += a.itens_entregues
	_hud_entregas.text = "%d %s" % [total, "entrega" if total == 1 else "entregas"]
	var minutos := _tempo_decorrido / 60.0
	_hud_ritmo.text = ("%.1f entregas por minuto" % (total / minutos)) if minutos > 0.25 else "medindo o ritmo..."
	_hud_tempo.text = "%02d:%02d de operação" % [int(_tempo_decorrido) / 60, int(_tempo_decorrido) % 60]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_H:
		if _hud != null:
			_hud.visible = not _hud.visible
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_C:
		alternar_camera_automatica()
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		var tela := get_window()
		tela.mode = (Window.MODE_MAXIMIZED if tela.mode == Window.MODE_FULLSCREEN
			else Window.MODE_FULLSCREEN)


func _arg_inteiro(nome: String, padrao: int) -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % nome):
			return int(a.get_slice("=", 1))
	return padrao


## Modo de medicao: com -- --medir=S, imprime o desempenho de cada robo apos S
## segundos e encerra. Nao altera nada na execucao normal.
func _relatorio_e_sair() -> void:
	var entregas := 0
	var desenc := 0
	var parados := 0
	var avaliados := 0
	for i in _agentes.size():
		var a := _agentes[i]
		entregas += a.itens_entregues
		desenc += a.desencalhes
		parados += a.quadros_sem_avancar
		avaliados += a.quadros_avaliados
		print("[medicao] robo %d: %d entregas, %d desencalhes" % [i, a.itens_entregues, a.desencalhes])
	print("[medicao] TOTAL robos=%d entregas=%d desencalhes=%d tempo_travado=%.1f%% reatribuicoes=%d"
		% [_agentes.size(), entregas, desenc, 100.0 * parados / maxi(avaliados, 1), reatribuicoes])
	get_tree().quit()


func _physics_process(delta: float) -> void:
	for agente in _agentes:
		if agente.alvo == null:
			continue
		var alvo := agente.alvo.global_position
		var d := Vector2(alvo.x - agente.global_position.x, alvo.z - agente.global_position.z).length()
		var p: Dictionary = _progresso.get(agente, {})
		var mudou: bool = (p.is_empty() or (p["alvo"] as Vector3).distance_to(alvo) > 0.01
			or p["carregando"] != agente.carregando_item)
		if mudou or d < float(p["melhor"]) - GANHO_MINIMO:
			_progresso[agente] = {"alvo": alvo, "carregando": agente.carregando_item,
				"melhor": d, "tempo": 0.0}
			continue
		p["tempo"] = float(p["tempo"]) + delta
		if p["tempo"] >= SEGUNDOS_SEM_PROGRESSO and not agente.carregando_item:
			var corredor := 15.1 if agente.global_position.x < 20.0 else 24.9
			_atribuir(agente, agente.global_position, corredor)
			reatribuicoes += 1
			_progresso.erase(agente)


func _animar_voos(delta: float) -> void:
	for i in range(_voos.size() - 1, -1, -1):
		var v: Dictionary = _voos[i]
		var agente: AgenteIA = v["agente"]
		v["t"] = minf(float(v["t"]) + delta / DURACAO_VOO, 1.0)
		var t: float = v["t"]
		var suave := t * t * (3.0 - 2.0 * t)
		var p := (v["origem"] as Vector3).lerp(agente.posicao_carga(), suave)
		p.y += sin(t * PI) * 0.9
		(v["copia"] as Node3D).global_position = p
		if t >= 1.0:
			(v["copia"] as Node).queue_free()
			if agente.carregando_item:
				agente.mostrar_carga(true)
			_voos.remove_at(i)


# --- Pilha de expedicao ------------------------------------------------------
# Ao lado da doca, encostada na parede norte (z -14.7). Fica fora do alcance
# dos robos: para entregar eles precisam chegar a menos de 2.56 u do centro da
# doca, em x 20, e a pilha comeca em x 24.6.
const PILHA_ORIGEM := Vector3(24.6, 0.0, -15.1)
const PILHA_COLUNAS := 3
const PILHA_FILEIRAS := 2
const PILHA_ANDARES := 4
const DURACAO_ENTREGA := 0.6
var _pilha_ocupadas := 0
var _pilha_nos: Array = []
var _expedicoes: Array = []
const DURACAO_EXPEDICAO := 1.6
var _voos_entrega: Array = []
var _malha_caixa: BoxMesh
var _mat_papelao: StandardMaterial3D


func _posicao_na_pilha(i: int) -> Vector3:
	var por_andar := PILHA_COLUNAS * PILHA_FILEIRAS
	var andar := i / por_andar
	var resto := i % por_andar
	return PILHA_ORIGEM + Vector3((resto % PILHA_COLUNAS) * 0.64, 0.23 + andar * 0.47,
		-(resto / PILHA_COLUNAS) * 0.64)


func _enviar_para_pilha(origem: Vector3) -> void:
	if _malha_caixa == null:
		_malha_caixa = BoxMesh.new()
		_malha_caixa.size = Vector3(0.6, 0.46, 0.6)
		_mat_papelao = StandardMaterial3D.new()
		_mat_papelao.albedo_color = Color(0.78, 0.6, 0.4)
		_mat_papelao.roughness = 0.9
	var capacidade := PILHA_COLUNAS * PILHA_FILEIRAS * PILHA_ANDARES
	var fica := _pilha_ocupadas < capacidade
	# Com a pilha cheia, a caixa pousa no topo e some: a pilha parece estavel.
	var indice := _pilha_ocupadas if fica else capacidade - 1 - (_pilha_ocupadas % PILHA_COLUNAS)
	_pilha_ocupadas += 1
	var copia := MeshInstance3D.new()
	copia.mesh = _malha_caixa
	copia.material_override = _mat_papelao
	add_child(copia)
	copia.global_position = origem
	_voos_entrega.append({"copia": copia, "origem": origem,
		"destino": _posicao_na_pilha(indice), "t": 0.0, "fica": fica})


func _animar_entregas(delta: float) -> void:
	for i in range(_voos_entrega.size() - 1, -1, -1):
		var v: Dictionary = _voos_entrega[i]
		v["t"] = minf(float(v["t"]) + delta / DURACAO_ENTREGA, 1.0)
		var t: float = v["t"]
		var suave := t * t * (3.0 - 2.0 * t)
		var p := (v["origem"] as Vector3).lerp(v["destino"], suave)
		p.y += sin(t * PI) * 1.2
		(v["copia"] as Node3D).global_position = p
		if t >= 1.0:
			if v["fica"]:
				_pilha_nos.append(v["copia"])
				if _pilha_nos.size() == PILHA_COLUNAS * PILHA_FILEIRAS * PILHA_ANDARES:
					_expedir_pilha()
			else:
				(v["copia"] as Node).queue_free()
			_voos_entrega.remove_at(i)


# --- Faixas no chao ----------------------------------------------------------
# Linhas amarelas ao longo das faces das prateleiras, so onde ha estante, como
# em armazens reais. Ficam alem do disco azul das caixas de coleta.
func _criar_faixas() -> void:
	var trechos: Array = preload("res://scripts/ia/colisores_prateleiras.gd").TRECHOS
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.92, 0.74, 0.14)
	mat.roughness = 0.9
	for par in FACES:
		var centro: float = par[0]
		var face: float = par[1]
		var x := face + signf(centro - face) * 1.25
		for t in trechos:
			var malha := BoxMesh.new()
			malha.size = Vector3(0.09, 0.012, absf(float(t[1]) - float(t[0])))
			var faixa := MeshInstance3D.new()
			faixa.mesh = malha
			faixa.material_override = mat
			add_child(faixa)
			faixa.global_position = Vector3(x, 0.006, (float(t[0]) + float(t[1])) * 0.5)


# --- Camera automatica ------------------------------------------------------
# Passeio lento sobre a regiao onde ha atividade, mirando o centro do grupo de
# robos, para a cena seguir em movimento enquanto alguem apresenta. Fica longe
# das laterais, onde o teto em arco e baixo e as vigas entram no quadro.
const PERIODO_PASSEIO := 70.0
var _camera_auto := false
var _fase_passeio := 0.0
var _jogador = null  # sem tipo: acessa campos do script da camera
var _foco_suave := Vector3.ZERO


func _ponto_passeio(fase: float) -> Vector3:
	return Vector3(20.0 + 4.0 * sin(fase), 4.0, -46.0 + 22.0 * cos(fase))


func _centro_dos_robos() -> Vector3:
	var c := Vector3.ZERO
	for a in _agentes:
		c += a.global_position
	c /= maxf(float(_agentes.size()), 1.0)
	c.y = 0.0
	return c


func alternar_camera_automatica() -> void:
	_jogador = get_node_or_null("../ProtoController")
	if _jogador == null:
		return
	_camera_auto = not _camera_auto
	if _camera_auto:
		_jogador.automatico = true
		_foco_suave = _centro_dos_robos()
	else:
		_jogador.retomar_controle()


func _mover_camera(delta: float) -> void:
	_fase_passeio = fmod(_fase_passeio + delta * TAU / PERIODO_PASSEIO, TAU)
	var p := _ponto_passeio(_fase_passeio)
	_foco_suave = _foco_suave.lerp(_centro_dos_robos(), 1.0 - exp(-delta * 0.6))
	var d := _foco_suave - p
	_jogador.global_position = p
	_jogador.rotation.y = atan2(-d.x, -d.z)
	var horizontal := Vector2(d.x, d.z).length()
	var inclinacao := -rad_to_deg(atan2(p.y + 1.3, horizontal))
	(_jogador.get_node("Head") as Node3D).rotation.x = deg_to_rad(clampf(inclinacao, -38.0, -15.0))


## Pilha completa: o lote inteiro desliza pela porta da parede norte e some, e
## uma pilha nova comeca no mesmo lugar.
func _expedir_pilha() -> void:
	var lote := []
	for n in _pilha_nos:
		lote.append({"no": n, "origem": (n as Node3D).global_position})
	_expedicoes.append({"lote": lote, "t": 0.0})
	_pilha_nos.clear()
	_pilha_ocupadas = 0


func _animar_expedicoes(delta: float) -> void:
	for i in range(_expedicoes.size() - 1, -1, -1):
		var e: Dictionary = _expedicoes[i]
		e["t"] = minf(float(e["t"]) + delta / DURACAO_EXPEDICAO, 1.0)
		var t: float = e["t"]
		var desloc := Vector3(0.0, 0.0, 2.2 * t * t)
		for item in e["lote"]:
			(item["no"] as Node3D).global_position = (item["origem"] as Vector3) + desloc
		if t >= 1.0:
			for item in e["lote"]:
				(item["no"] as Node).queue_free()
			_expedicoes.remove_at(i)

