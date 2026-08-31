class_name RedeNeural
extends RefCounted

var w1: Array = []
var w2: Array = []
var w3: Array = []
var b1: Array = []
var b2: Array = []
var b3: Array = []

func carregar(caminho: String) -> bool:
	var file := FileAccess.open(caminho, FileAccess.READ)
	if not file:
		push_error("RedeNeural: nao foi possivel abrir %s" % caminho)
		return false
	var dados = JSON.parse_string(file.get_as_text())
	file.close()
	if not dados is Dictionary:
		push_error("RedeNeural: JSON invalido em %s" % caminho)
		return false
	w1 = dados["w1"]
	w2 = dados["w2"]
	w3 = dados["w3"]
	b1 = dados["b1"]
	b2 = dados["b2"]
	b3 = dados["b3"]
	return true

func forward(x: Array) -> Array:
	var h1 := _matmul_add_bias(x, w1, b1)
	_tanh_inplace(h1)
	var h2 := _matmul_add_bias(h1, w2, b2)
	_tanh_inplace(h2)
	# camada de saida sem ativacao (igual ao rede_transfer.py)
	return _matmul_add_bias(h2, w3, b3)

# x @ w + b  (x: [in], w: [in][out], b: [out]) -> [out]
func _matmul_add_bias(x: Array, w: Array, b: Array) -> Array:
	var n_out: int = (w[0] as Array).size()
	var result: Array = []
	result.resize(n_out)
	for j in n_out:
		result[j] = float(b[j])
	for i in x.size():
		var xi := float(x[i])
		if xi == 0.0:
			continue
		var row: Array = w[i]
		for j in n_out:
			result[j] += xi * float(row[j])
	return result

func _tanh_inplace(arr: Array) -> void:
	for i in arr.size():
		arr[i] = tanh(float(arr[i]))
