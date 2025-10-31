extends Control

var time = 0.0

func _process(delta: float) -> void:
	time += delta
	$RightPanel/Time/TimeOutput.text = str(int(round(time))) + "s"

func on_energy_updated(energy):
	$RightPanel/Energy/EnergyBar.value = energy
	var style = StyleBoxFlat.new()
	style.set_corner_radius_all(6)
	if energy < 25:
		style.bg_color = Color(1, 0, 0)
	elif energy < 75:
		style.bg_color = Color(1, 1, 0)
	else:
		style.bg_color = Color(0, 1, 0)
		
	$RightPanel/Energy/EnergyBar.add_theme_stylebox_override("fill", style)
	
func on_max_depth_updated(maxDepth):
	$RightPanel/Depth/DepthOutput.text = str(maxDepth) + "m"
