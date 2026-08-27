package haversine

import "core:math"

square :: proc(a: f64) -> f64 {
	return a * a
}

haversine :: proc(lon1, lat1, lon2, lat2: f64, earth_radius: f64 = 6372.8) -> f64 {
	d_lat := math.to_radians(lat2 - lat1)
	d_lon := math.to_radians(lon2 - lon1)

	lat1 := math.to_radians(lat1)
	lat2 := math.to_radians(lat2)

	a :=
		square(math.sin(d_lat / 2.0)) +
		math.cos(lat1) * math.cos(lat2) * square(math.sin(d_lon / 2))

	c := 2.0 * math.asin(math.sqrt(a))

	return earth_radius * c
}
