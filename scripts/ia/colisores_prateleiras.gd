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
const Z_INICIO := -98.0
const Z_FIM := -23.8
const MARGEM_Z := 2.4  # meia prateleira em cada ponta

const LAYER_ESTATICOS := 1


func _ready() -> void:
	var z0 := Z_INICIO - MARGEM_Z
	var z1 := Z_FIM + MARGEM_Z
	var comprimento := absf(z1 - z0)
	var centro_z := (z0 + z1) * 0.5

	for x in X_FILEIRAS:
		var corpo := StaticBody3D.new()
		corpo.name = "ColisorFileira_%d" % int(round(x))
		corpo.collision_layer = LAYER_ESTATICOS
		corpo.collision_mask = 0
		add_child(corpo)
		corpo.global_position = Vector3(x, ALTURA * 0.5, centro_z)

		var caixa := BoxShape3D.new()
		caixa.size = Vector3(LARGURA, ALTURA, comprimento)

		var forma := CollisionShape3D.new()
		forma.shape = caixa
		corpo.add_child(forma)

	print("[colisores] %d fileiras, corredor livre = %.1fu (%.1fx a largura do agente)"
		% [X_FILEIRAS.size(), 9.8 - LARGURA, (9.8 - LARGURA) / 1.2])
