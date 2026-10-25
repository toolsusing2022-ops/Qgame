# CIEDE2000 colour difference, ported from tools/validate_level.py (used by the palette-compat check GS-13.9 d).
extends RefCounted


static func delta_e_hex(h1: String, h2: String) -> float:
	return ciede2000(srgb_to_lab(Color.html(h1)), srgb_to_lab(Color.html(h2)))


static func srgb_to_lab(c: Color) -> Vector3:
	var r := _lin(c.r8)
	var g := _lin(c.g8)
	var b := _lin(c.b8)
	var x := (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047
	var y := 0.2126729 * r + 0.7151522 * g + 0.0721750 * b
	var z := (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883
	var fx := _f(x)
	var fy := _f(y)
	var fz := _f(z)
	return Vector3(116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz))


static func _lin(v8: int) -> float:
	var c := v8 / 255.0
	return pow((c + 0.055) / 1.055, 2.4) if c > 0.04045 else c / 12.92


static func _f(t: float) -> float:
	var d := 6.0 / 29.0
	return pow(t, 1.0 / 3.0) if t > d * d * d else t / (3.0 * d * d) + 4.0 / 29.0


static func ciede2000(lab1: Vector3, lab2: Vector3) -> float:
	var l1 := lab1.x
	var a1 := lab1.y
	var b1 := lab1.z
	var l2 := lab2.x
	var a2 := lab2.y
	var b2 := lab2.z
	var c_bar := (Vector2(a1, b1).length() + Vector2(a2, b2).length()) / 2.0
	var c7 := pow(c_bar, 7.0)
	var g := 0.5 * (1.0 - sqrt(c7 / (c7 + pow(25.0, 7.0))))
	var a1p := (1.0 + g) * a1
	var a2p := (1.0 + g) * a2
	var c1p := Vector2(a1p, b1).length()
	var c2p := Vector2(a2p, b2).length()
	var h1p := fposmod(rad_to_deg(atan2(b1, a1p)), 360.0) if c1p != 0.0 else 0.0
	var h2p := fposmod(rad_to_deg(atan2(b2, a2p)), 360.0) if c2p != 0.0 else 0.0
	var dl := l2 - l1
	var dc := c2p - c1p
	var dh := 0.0
	if c1p * c2p != 0.0:
		dh = h2p - h1p
		if dh > 180.0:
			dh -= 360.0
		elif dh < -180.0:
			dh += 360.0
	var d_big_h := 2.0 * sqrt(c1p * c2p) * sin(deg_to_rad(dh / 2.0))
	var l_bar := (l1 + l2) / 2.0
	var cp_bar := (c1p + c2p) / 2.0
	var h_bar: float
	if c1p * c2p == 0.0:
		h_bar = h1p + h2p
	elif absf(h1p - h2p) <= 180.0:
		h_bar = (h1p + h2p) / 2.0
	elif h1p + h2p < 360.0:
		h_bar = (h1p + h2p + 360.0) / 2.0
	else:
		h_bar = (h1p + h2p - 360.0) / 2.0
	var t := (1.0 - 0.17 * cos(deg_to_rad(h_bar - 30.0)) + 0.24 * cos(deg_to_rad(2.0 * h_bar))
		+ 0.32 * cos(deg_to_rad(3.0 * h_bar + 6.0)) - 0.20 * cos(deg_to_rad(4.0 * h_bar - 63.0)))
	var d_theta := 30.0 * exp(-pow((h_bar - 275.0) / 25.0, 2.0))
	var cp7 := pow(cp_bar, 7.0)
	var r_c := 2.0 * sqrt(cp7 / (cp7 + pow(25.0, 7.0)))
	var s_l := 1.0 + 0.015 * pow(l_bar - 50.0, 2.0) / sqrt(20.0 + pow(l_bar - 50.0, 2.0))
	var s_c := 1.0 + 0.045 * cp_bar
	var s_h := 1.0 + 0.015 * cp_bar * t
	var r_t := -sin(deg_to_rad(2.0 * d_theta)) * r_c
	return sqrt(pow(dl / s_l, 2.0) + pow(dc / s_c, 2.0) + pow(d_big_h / s_h, 2.0)
		+ r_t * (dc / s_c) * (d_big_h / s_h))
