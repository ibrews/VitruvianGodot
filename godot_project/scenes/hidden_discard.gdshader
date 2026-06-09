shader_type spatial;
// Fully invisible material — used to REMOVE the baked scalp "dome" (VitScalp) that
// read as a helmet whenever the hair cards thinned out. Discards every fragment and
// casts no shadow, so the dome is gone entirely; the hair cards are the only crown hair.
render_mode unshaded, shadows_disabled, cull_disabled;

void fragment() {
	discard;
}
