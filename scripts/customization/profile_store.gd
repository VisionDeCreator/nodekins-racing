class_name CustomizationProfileStore
extends RefCounted
const DEFAULT_PATH: String = "user://customization/profile_v1.json"
var path: String = DEFAULT_PATH
var status: String = ""

func save_profile(profile: CustomizationProfile, library: CustomizationLibrary) -> bool:
	if not library.accepts(profile):
		status = "Unknown customization ID. Changes were not saved."
		return false
	var absolute: String = ProjectSettings.globalize_path(path)
	if DirAccess.make_dir_recursive_absolute(absolute.get_base_dir()) != OK:
		status = "Cannot create the profile folder."
		return false
	var file := FileAccess.open(path + ".tmp",FileAccess.WRITE)
	if file == null:
		status = "Cannot write the profile. Please try again."
		return false
	file.store_string(JSON.stringify({"version":CustomizationProfile.WIRE_VERSION,"values":profile.to_values()}))
	file.flush()
	var write_ok: bool = file.get_error() == OK
	file.close()
	if not write_ok:
		status = "Could not finish saving. Your previous profile is intact."
		return false
	# Keep the last valid file; never replace the backup with malformed input.
	if _read(path,library) != null:
		if DirAccess.copy_absolute(absolute,absolute + ".bak") != OK:
			status = "Could not back up the previous profile."
			return false
	if DirAccess.rename_absolute(absolute + ".tmp",absolute) != OK:
		status = "Could not replace the saved profile. Please try again."
		return false
	status = "Saved automatically"
	return true

func load_profile(library: CustomizationLibrary) -> CustomizationProfile:
	var profile: CustomizationProfile = _read(path,library)
	if profile != null:
		status = "Saved profile loaded"
		return profile
	profile = _read(path + ".bak",library)
	if profile != null:
		status = "Recovered the previous saved profile"
		return profile
	status = "Choose your look" if not FileAccess.file_exists(path) else "Saved profile could not be read. Using defaults."
	return CustomizationProfile.new()

func _read(filename: String, library: CustomizationLibrary) -> CustomizationProfile:
	if not FileAccess.file_exists(filename):
		return null
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(filename)) != OK:
		return null
	var data: Variant = parser.data
	if not data is Dictionary or data.size() != 2 or data.get("version") != CustomizationProfile.WIRE_VERSION or not data.has("values"):
		return null
	var profile: CustomizationProfile = CustomizationProfile.from_values(data["values"])
	return profile if library.accepts(profile) else null
