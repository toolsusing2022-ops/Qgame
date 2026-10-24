# Probe: SceneTree.quit(code) sets the process exit code in headless script mode.
extends SceneTree

func _init():
	quit(3)
