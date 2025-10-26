extends Control

var time = 0.0

func _process(delta: float) -> void:
	time += delta
	$RightPanel/Time/TimeOutput.text = str(int(round(time))) + "s"

func on_energy_updated(energy):
	$RightPanel/Energy/EnergyBar.value = energy
	
func on_max_depth_updated(maxDepth):
	$RightPanel/Depth/DepthOutput.text = str(maxDepth) + "m"
