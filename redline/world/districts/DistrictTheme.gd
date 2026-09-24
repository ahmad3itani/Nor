class_name DistrictTheme
extends Resource
## A district's visual identity (bible §25 "each district gets unique palette,
## architecture, parallax layers, weather, lighting language"). Placeholder
## renderers read these colors until the Art Bible's real assets exist.

@export var district_name: String = ""
@export_group("Sky & skyline")
@export var sky_top: Color = Color("0b0a12")
@export var sky_bottom: Color = Color("24162a")
@export var far_color: Color = Color("1a1524")
@export var mid_color: Color = Color("241c30")
@export var window_colors: PackedColorArray = [Color("ffcf5a"), Color("58e0e8"), Color("e8283c")]
@export_range(0.0, 1.0) var window_density: float = 0.12
@export_group("Geometry")
@export var solid_color: Color = Color("2c2636")
@export var edge_color: Color = Color("5c5470")
@export var one_way_color: Color = Color("56727f")
@export_group("Weather")
@export var rain: bool = true
@export var rain_color: Color = Color(0.6, 0.7, 0.9, 0.35)
@export var rain_drops: int = 90
@export var rain_angle_deg: float = 12.0
