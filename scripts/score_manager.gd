extends Node

class_name ScoreManager

signal energy_changed(new_energy)

var energy: int = 0

func reset():
	energy = 100
	emit_signal("energy_changed", energy)

func change_energy(delta: int):
	energy += delta
	emit_signal("energy_changed", energy)
