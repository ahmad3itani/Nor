class_name SettingsPageData
extends Resource
## One Settings page (D4 §3.2): a title and its rows in display order. Pages
## are one level deep under the main category list; SettingsMenu adds the
## Reset and Back rows, so every page backs out the same way (R03.17).

## Localization (D5): player-visible text fields -> max source chars.
const LOC_FIELDS := {"title": 32, "link_label": 32}
const LOC_EXEMPT := ["id", "row_keys", "special"]

## Page id (SettingsMenu.page while it is shown).
@export var id: StringName = &""
## Heading shown at the top of the page.
@export var title: String = ""
## Row text of the main-page link ("Assists…"); empty = not on the main list.
@export var link_label: String = ""
## Rows this page owns (each persisted key has exactly one owner def, SE-1).
@export var rows: Array[SettingDef] = []
## Rows borrowed from other pages by key (the first-run quick page).
@export var row_keys: PackedStringArray = []
## Show the catalog's assist header line under the title.
@export var show_assist_header: bool = false
## Add "Reset this page…" above Back.
@export var reset_row: bool = true
## Hidden (link and page) unless DevActions.available().
@export var dev_only: bool = false
## Special pages (&"controls", &"quick") add rows built in code after these.
@export var special: StringName = &""
