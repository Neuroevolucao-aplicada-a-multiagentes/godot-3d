extends Node3D

# As prateleiras sao malhas .glb importadas sem colisao. Sem os colisores
# gerados aqui, os RayCast3D do agente nao acertam nada e as 8 entradas de
# obstaculo da rede ficam fixas em 1.0 -- ou seja, a rede navega cega e os
# agentes atravessam as estruturas.
#
# Gera uma caixa por FILEIRA, e nao por prateleira: as fileiras sao continuas
# ao longo de Z, entao um colisor por fileira basta e custa muito menos que 48.
#
# LARGURA e o unico numero que precisa de conferencia visual no editor: ele
# define a largura efetiva do obstaculo e, por consequencia, a largura livre
# do corredor (espacamento 9.8 - LARGURA).

const LARGURA := 2.0
const ALTURA := 4.0
const X_FILEIRAS: Array[float] = [10.2, 20.0, 29.8]

# Cada fileira e cortada por dois corredores transversais, entao vira tres
# trechos. Os intervalos abaixo (z inicial, z final, em coordenada global)
# tem de acompanhar as prateleiras que sobraram em main.tscn.
const TRECHOS: Array = [
	[-102.5, -77.8],
	[-68.0, -53.2],
	[-42.9, -23.5],
]

const LAYER_ESTATICOS := 1


func _ready() -> void:
	var n := 0
	for x in X_FILEIRAS:
		for t in TRECHOS:
			var z0: float = t[0]
			var z1: float = t[1]
			var corpo := StaticBody3D.new()
			corpo.name = "ColisorFileira_%d_%d" % [int(round(x)), n]
			corpo.collision_layer = LAYER_ESTATICOS
			corpo.collision_mask = 0
			add_child(corpo)
			corpo.global_position = Vector3(x, ALTURA * 0.5, (z0 + z1) * 0.5)

			var caixa := BoxShape3D.new()
			caixa.size = Vector3(LARGURA, ALTURA, absf(z1 - z0))

			var forma := CollisionShape3D.new()
			forma.shape = caixa
			corpo.add_child(forma)
			n += 1

	var vao_transversal: float = TRECHOS[1][0] - TRECHOS[0][1]
	print("[colisores] %d fileiras x %d trechos | corredor longitudinal %.1fu | transversal %.1fu"
		% [X_FILEIRAS.size(), TRECHOS.size(), 9.8 - LARGURA, vao_transversal])
