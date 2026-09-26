class_name PlatformBackends
extends RefCounted
## Backend factory (D1 §6.1). The repo holds exactly one branch: local. A
## storefront adapter is a documented slot (Docs/PLATFORM_SERVICES.md), added
## here only by a future human decision; until then any other id warns and
## plays on the local backend.


static func create(id: StringName) -> PlatformBackend:
	match id:
		&"local":
			return LocalPlatformBackend.new()
	push_warning("PlatformBackends: unknown backend '%s', using local" % id)
	return LocalPlatformBackend.new()
