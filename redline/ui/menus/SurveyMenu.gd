extends MenuScreen
## Post-slice survey (M4). One question per page, every answer a button, so a
## controller finishes it without a keyboard. Questions come from
## PlaytestConfig; ten of them map 1:1 to the bible §44 success test.
## Any question can be skipped; answers are saved into the session file.

const SCALE_LABELS := ["1  Strongly disagree", "2  Disagree", "3  Neutral", "4  Agree", "5  Strongly agree"]

var answers: Dictionary = {}
var _index: int = 0


func open_menu() -> void:
	answers = {}
	_index = 0
	super.open_menu()
	focus_index(0)


func questions() -> Array[SurveyQuestion]:
	return Playtest.config.survey


func rebuild() -> void:
	clear_body()
	_panel.custom_minimum_size = Vector2(380, 0)
	var qs := questions()
	add_label("PLAYTEST SURVEY", UiTheme.ACCENT, UiTheme.FONT_SIZE + 2)
	if _index >= qs.size():
		add_label("Thank you! Your answers are saved with this run.")
		add_label("Your session file: %s" % ProjectSettings.globalize_path(Playtest.session_path), UiTheme.MUTED, UiTheme.FONT_SIZE - 1)
		add_button("Done", close_menu)
		return
	var q := qs[_index]
	add_label("%d / %d" % [_index + 1, qs.size()], UiTheme.MUTED)
	add_label(q.text)
	match q.kind:
		SurveyQuestion.Kind.SCALE:
			for i in SCALE_LABELS.size():
				add_button(SCALE_LABELS[i], answer.bind(i + 1))
		SurveyQuestion.Kind.YES_NO:
			add_button("Yes", answer.bind(true))
			add_button("No", answer.bind(false))
		SurveyQuestion.Kind.CHOICE:
			for i in q.choices.size():
				add_button(q.choices[i], answer.bind(i))
	add_button("Skip", answer.bind(null))


## Records the current question's answer (null = skipped) and advances.
func answer(value: Variant) -> void:
	var qs := questions()
	if _index >= qs.size():
		return
	if value != null:
		answers[qs[_index].id] = value
	_index += 1
	if _index >= qs.size():
		Playtest.submit_survey(answers)
	rebuild()
	focus_index(0)
