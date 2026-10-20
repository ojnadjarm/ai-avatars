extends RefCounted
## ZoneBanner timing (slide in, 2.5 s hold, slide out) and the 3 s re-entry rule.

const ZoneBanner := preload("res://scripts/hud/zone_banner.gd")

var failure_message: String = ""


func run() -> bool:
	return _test_timing() and _test_reentry() and _test_other_zone() and _test_swap_while_shown()


func _fail(msg: String) -> bool:
	failure_message = msg
	return false


func _banner() -> ZoneBanner:
	return ZoneBanner.new()


func _test_timing() -> bool:
	var b := _banner()
	if b.phase() != ZoneBanner.Phase.HIDDEN:
		return _fail("new banner not hidden")
	if not b.enter_zone("Mirror Lake"):
		return _fail("first entry ignored")
	if b.phase() != ZoneBanner.Phase.IN or b.shown() != 0.0:
		return _fail("entry did not start the slide-in")
	b.tick(ZoneBanner.SLIDE * 0.5)
	if b.phase() != ZoneBanner.Phase.IN or not (b.shown() > 0.0 and b.shown() < 1.0):
		return _fail("mid slide-in shown=%f" % b.shown())
	b.tick(ZoneBanner.SLIDE * 0.5 + 0.01)
	if b.phase() != ZoneBanner.Phase.HOLD or b.shown() != 1.0:
		return _fail("no hold after the slide")
	b.tick(ZoneBanner.HOLD - 0.05)
	if b.phase() != ZoneBanner.Phase.HOLD:
		return _fail("hold shorter than %.1f s" % ZoneBanner.HOLD)
	b.tick(0.1)
	if b.phase() != ZoneBanner.Phase.OUT or not (b.shown() > 0.0 and b.shown() < 1.0):
		return _fail("no slide-out after the hold")
	b.tick(ZoneBanner.SLIDE)
	if b.phase() != ZoneBanner.Phase.HIDDEN or b.shown() != 0.0:
		return _fail("still shown after slide-out")
	b.free()
	return true


func _test_reentry() -> bool:
	var b := _banner()
	b.enter_zone("Moss Gate")
	b.tick(1.0)
	b.exit_zone("Moss Gate")
	b.tick(2.0)
	if b.enter_zone("Moss Gate"):
		return _fail("re-entry 2 s after leaving was shown")
	b.tick(1.0)
	b.exit_zone("Moss Gate")
	b.tick(ZoneBanner.REENTRY - 0.1)
	if b.enter_zone("Moss Gate"):
		return _fail("re-entry 2.9 s after leaving was shown")
	b.exit_zone("Moss Gate")
	b.tick(ZoneBanner.REENTRY + 0.1)
	if not b.enter_zone("Moss Gate"):
		return _fail("entry 3.1 s after leaving was ignored")
	if b.zone != "Moss Gate" or b.phase() != ZoneBanner.Phase.IN:
		return _fail("late re-entry did not slide in")
	b.free()
	return true


func _test_other_zone() -> bool:
	var b := _banner()
	b.enter_zone("Spiral Meadow")
	b.tick(ZoneBanner.SLIDE * 2.0 + ZoneBanner.HOLD + 0.1)
	b.exit_zone("Spiral Meadow")
	b.tick(0.5)
	if not b.enter_zone("Resting Oak"):
		return _fail("a different zone within 3 s was ignored")
	b.free()
	return true


func _test_swap_while_shown() -> bool:
	var b := _banner()
	b.enter_zone("Whispering Hollow")
	b.tick(1.0)
	b.enter_zone("Cerulean Ring")
	if b.zone != "Cerulean Ring" or b.phase() != ZoneBanner.Phase.HOLD:
		return _fail("new zone while shown: zone=%s phase=%d" % [b.zone, b.phase()])
	b.tick(ZoneBanner.HOLD - 0.05)
	if b.phase() != ZoneBanner.Phase.HOLD:
		return _fail("swapped zone did not get a full hold")
	b.free()
	return true
