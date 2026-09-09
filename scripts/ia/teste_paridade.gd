extends Node3D

## Teste de paridade entre a implementacao Python e a portada para GDScript.
##
## Le tests/golden_vectors.json, gerado no repositorio de treino por
## src/gerar_golden_vectors.py, e verifica que esta implementacao reproduz os
## mesmos numeros. E a protecao contra a classe de bug que ja apareceu tres
## vezes neste projeto: a codificacao das entradas divergindo em silencio,
## sem erro, com a rede simplesmente operando fora da distribuicao.
##
## Como usar: adicione este script a um Node3D numa cena vazia e execute-a.
## O resultado sai no painel Saida.
##
## COBERTURA
##   1. Forward pass, exato. Alimenta os 16 inputs do fixture e compara as 2
##      saidas. Valida pesos, multiplicacao de matriz, tanh e saida linear.
##   2. Entradas 0,1,3,4,5,7, exato. Sao adimensionais, entao independem da
##      escala do mundo e podem ser comparadas diretamente com o fixture.
##      Cobrem justamente onde os bugs historicos aconteceram: direcao
##      unitaria (0,1) e tempo normalizado (7).
##   3. Entradas 2,6,8-15, por invariante. Dependem da escala do mundo, entao
##      sao checadas por faixa e por coerencia, nao por igualdade.

const CAMINHO_FIXTURE := "res://assets/golden_vectors.json"
const CAMINHO_REDE := "res://assets/melhor_rede_fase5.json"
const TOLERANCIA := 1e-4

var _falhas := 0
var _checagens := 0


func _ready() -> void:
	var fixture := _carregar_fixture()
	if fixture.is_empty():
		return

	print("=== paridade Python <-> GDScript ===")
	_testar_arquitetura(fixture)
	_testar_forward(fixture)
	_testar_entradas_adimensionais(fixture)

	print("---")
	if _falhas == 0:
		print("OK: %d checagens, nenhuma divergencia" % _checagens)
	else:
		printerr("FALHOU: %d de %d checagens divergiram" % [_falhas, _checagens])

	# Encerra sozinho para permitir execucao por linha de comando:
	#   godot --headless --path . res://teste_paridade.tscn
	if not Engine.is_editor_hint():
		get_tree().quit(1 if _falhas > 0 else 0)


func _carregar_fixture() -> Dictionary:
	var arq := FileAccess.open(CAMINHO_FIXTURE, FileAccess.READ)
	if arq == null:
		printerr("fixture nao encontrado em %s" % CAMINHO_FIXTURE)
		printerr("copie tests/golden_vectors.json do repositorio de treino para assets/")
		return {}
	var dados = JSON.parse_string(arq.get_as_text())
	arq.close()
	if not dados is Dictionary:
		printerr("fixture invalido")
		return {}
	return dados


func _testar_arquitetura(fixture: Dictionary) -> void:
	# O JSON entrega numeros como float, entao converte antes de comparar:
	# [16.0, 32.0, 16.0, 2.0] != [16, 32, 16, 2] em GDScript.
	var esperada := []
	for v in (fixture["arquitetura"] as Array):
		esperada.append(int(v))

	var rede := RedeNeural.new()
	if not rede.carregar(CAMINHO_REDE):
		_reprovar("arquitetura", "nao foi possivel carregar a rede")
		return

	var entradas: int = (rede.w1 as Array).size()
	var ocultas_1: int = (rede.w1[0] as Array).size()
	var ocultas_2: int = (rede.w2[0] as Array).size()
	var saidas: int = (rede.w3[0] as Array).size()
	var obtida := [entradas, ocultas_1, ocultas_2, saidas]

	if obtida == esperada:
		_aprovar("arquitetura %s" % str(obtida))
	else:
		_reprovar("arquitetura", "esperava %s, veio %s" % [str(esperada), str(obtida)])


func _testar_forward(fixture: Dictionary) -> void:
	var rede := RedeNeural.new()
	if not rede.carregar(CAMINHO_REDE):
		_reprovar("forward", "nao foi possivel carregar a rede")
		return

	var casos: Array = fixture["casos"]
	var pior := 0.0
	for i in casos.size():
		var caso: Dictionary = casos[i]
		var saida := rede.forward(caso["inputs"])
		var esperada: Array = caso["saida"]

		if saida.size() != esperada.size():
			_reprovar("forward caso %d" % i, "tamanho da saida difere")
			continue

		var erro := 0.0
		for j in saida.size():
			erro = maxf(erro, absf(float(saida[j]) - float(esperada[j])))
		pior = maxf(pior, erro)

		if erro > TOLERANCIA:
			_reprovar("forward caso %d" % i,
				"erro %.9f | esperado (%.6f, %.6f) | obtido (%.6f, %.6f)"
				% [erro, esperada[0], esperada[1], saida[0], saida[1]])
		else:
			_aprovar("forward caso %d (erro %.9f)" % [i, erro])

	print("  pior erro no forward: %.9f" % pior)


func _testar_entradas_adimensionais(fixture: Dictionary) -> void:
	# Indices que nao dependem da escala do mundo e por isso podem ser
	# comparados diretamente com o fixture do Python.
	var indices := [0, 1, 3, 4, 5, 7]
	var casos: Array = fixture["casos"]
	var duracao: float = float(fixture["constantes"]["duracao_geracao"])

	for i in casos.size():
		var caso: Dictionary = casos[i]
		var esperado: Array = caso["inputs"]
		var obtido := _montar_entradas_adimensionais(caso, fixture, duracao)

		for k in indices:
			var erro := absf(obtido[k] - float(esperado[k]))
			if erro > TOLERANCIA:
				_reprovar("caso %d entrada %d" % [i, k],
					"esperado %.6f, obtido %.6f" % [esperado[k], obtido[k]])
			else:
				_aprovar("caso %d entrada %d" % [i, k])

		# Invariantes de faixa, validos em qualquer escala.
		var norma_alvo := sqrt(obtido[0] * obtido[0] + obtido[1] * obtido[1])
		var norma_ent := sqrt(obtido[4] * obtido[4] + obtido[5] * obtido[5])
		_conferir(absf(norma_alvo - 1.0) < 1e-3, "caso %d: direcao do alvo unitaria" % i)
		_conferir(absf(norma_ent - 1.0) < 1e-3, "caso %d: direcao da entrega unitaria" % i)
		_conferir(esperado[3] == 0.0 or esperado[3] == 1.0, "caso %d: flag de carga binaria" % i)
		_conferir(float(esperado[2]) >= 0.0 and float(esperado[2]) <= 1.0,
			"caso %d: distancia normalizada em [0,1]" % i)
		_conferir(float(esperado[6]) >= 0.0 and float(esperado[6]) <= 1.0,
			"caso %d: modulo de velocidade em [0,1]" % i)
		for r in range(8, 16):
			_conferir(float(esperado[r]) >= 0.0 and float(esperado[r]) <= 1.0,
				"caso %d: raio %d em [0,1]" % [i, r - 8])


## Reproduz as entradas adimensionais com a MESMA formula de agente_ia.gd.
## Mantenha as duas em sincronia: se a formula mudar la, muda aqui.
func _montar_entradas_adimensionais(caso: Dictionary, fixture: Dictionary,
									duracao: float) -> Array:
	var pos: Array = caso["pos"]
	var mundo: Dictionary = fixture["mundo"]
	var pacote: Array = mundo["pacote"]
	var entrega: Array = mundo["entrega"]
	var carregando: bool = caso["carregando"]

	var alvo: Array = entrega if carregando else pacote

	var dx := float(alvo[0]) - float(pos[0])
	var dy := float(alvo[1]) - float(pos[1])
	var dist := sqrt(dx * dx + dy * dy)

	var ex := float(entrega[0]) - float(pos[0])
	var ey := float(entrega[1]) - float(pos[1])
	var dist_ent := sqrt(ex * ex + ey * ey)

	var saida := []
	saida.resize(16)
	for i in 16:
		saida[i] = 0.0
	saida[0] = dx / (dist + 1e-6)
	saida[1] = dy / (dist + 1e-6)
	saida[3] = 1.0 if carregando else 0.0
	saida[4] = ex / (dist_ent + 1e-6)
	saida[5] = ey / (dist_ent + 1e-6)
	saida[7] = minf(float(caso["tempo_vivo"]) / duracao, 1.0)
	return saida


func _aprovar(_rotulo: String) -> void:
	_checagens += 1


func _reprovar(rotulo: String, detalhe: String) -> void:
	_checagens += 1
	_falhas += 1
	printerr("  FALHA %s: %s" % [rotulo, detalhe])


func _conferir(condicao: bool, rotulo: String) -> void:
	_checagens += 1
	if not condicao:
		_falhas += 1
		printerr("  FALHA %s" % rotulo)
