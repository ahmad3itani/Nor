#!/usr/bin/env python3
"""Builds tools/assetgen/sound_manifest.json (REDLINE sound overhaul, Sound Director).

Run: python3 build_sound_manifest.py [--check]
--check verifies every SfxDefinition id in redline/data/audio/placeholder_sfx.tres
is covered, ids are unique, and prints the credit estimate per priority.

Cost model (assumption, verify on the first generations of each kind):
  eleven_text_to_sound_v2: ~25 credits per generated second, min 50 per call
    (pilot: 2.0 s slash ~ 50 credits).
  eleven_music_v2: ~15 credits per second (~900 per 60 s).
"""
import json, math, re, sys, pathlib

HERE = pathlib.Path(__file__).resolve().parent
OUT = HERE / "sound_manifest.json"
BANK = HERE.parent.parent / "data" / "audio" / "placeholder_sfx.tres"

TAIL = " Isolated single sound effect, close-mic, dry, clean, no music, no voice, no speech."
SHEET = (" Several separate takes one after another, each clearly separated by half a second"
         " of total silence, slight natural variation between takes, no music, no voice.")
LOOPT = " Continuous seamless ambience loop, steady density, no sudden events, no music, no voice, no speech."

# id, category, owner, priority, prompt, game duration_s, gen_duration_s, loop, variations,
# gen_mode, post_process, mix_db (target SfxDefinition.volume_db / bus-relative), notes, used_by
E = []


def add(id, cat, pri, prompt, dur, gen=None, loop=False, var=1, mode="single", pp=None,
        mix_db=None, notes="", used_by="", owner=None, existing=False, infl=0.6):
    if gen is None:
        gen = max(dur, 1.0)
    if pp is None:
        pp = {"sfx": "sfx_std", "ui": "ui_std", "footstep": "footstep_sheet",
              "ambience": "amb_loop", "music": "music_loop", "stinger": "stinger_std"}[cat]
    if owner is None:
        owner = "music_amb" if cat in ("ambience", "music") else "sfx"
    if cat == "music":
        credits = math.ceil(gen * 15)
    else:
        credits = max(50, math.ceil(gen * 25))
    E.append({
        "id": id, "category": cat, "priority": pri, "owner": owner,
        "existing_id": existing,
        "prompt": prompt, "duration_s": dur, "gen_duration_s": gen, "loop": loop,
        "variations": var, "gen_mode": mode, "generations": 1,
        "prompt_influence": infl if cat != "music" else None,
        "model": "eleven_music_v2" if cat == "music" else "eleven_text_to_sound_v2",
        "post_process": pp, "mix_db": mix_db, "est_credits": credits,
        "used_by": used_by, "notes": notes,
    })


X = dict(existing=True)

# ---------------------------------------------------------------- movement (existing)
add("jump", "sfx", 1, "Light agile jump push-off: a quick cloth-and-coat whoosh with a soft rubber boot scuff on wet concrete and a faint electric crackle from a chest reactor." + SHEET,
    0.25, gen=2.0, var=2, mode="sheet", pp="sfx_sheet_slice", mix_db=-13,
    used_by="PlayerFeedback._on_jumped", notes="Must never be louder than land. Keep attack under 5 ms so input feels instant.", **X)
add("jump_slide", "sfx", 1, "Low sliding jump out of a floor slide: boot sole squeak releasing from concrete, heavier coat whoosh rising upward, tiny electric crackle." + TAIL,
    0.3, gen=1.0, mix_db=-13, used_by="PlayerFeedback._on_jumped(kind=slide)", **X)
add("land_soft", "sfx", 1, "Soft landing of a light-footed person on wet concrete: a muted boot thud with a small splash-free scuff and coat settle." + SHEET,
    0.2, gen=2.0, var=2, mode="sheet", pp="sfx_sheet_slice", mix_db=-12,
    used_by="PlayerFeedback._on_landed (volume_scale 0.5..1)", notes="cooldown 0.05 stays", **X)
add("land_hard", "sfx", 1, "Heavy hard landing from a high fall onto concrete: deep boot impact thump, low body-weight crunch, grit and small debris skitter, short low rumble tail." + SHEET,
    0.45, gen=2.5, var=2, mode="sheet", pp="sfx_sheet_slice", mix_db=-6,
    used_by="PlayerFeedback._on_landed", notes="Pair with camera landing impulse; low end 60-120 Hz is the weight.", **X)
add("slide", "sfx", 1, "Fast floor slide: rubber boots and a long coat scraping across gritty wet concrete, a smooth friction hiss that fades out." + TAIL,
    0.5, gen=1.0, mix_db=-14, used_by="PlayerFeedback state slide", notes="Played once on slide entry; 0.5 s scrape with fade covers a typical slide.", **X)
add("dodge", "sfx", 1, "Quick evasive sidestep: sharp short air whoosh of a coat, a light electric shimmer as a body phases, very fast and airy." + SHEET,
    0.25, gen=2.0, var=2, mode="sheet", pp="sfx_sheet_slice", mix_db=-12,
    used_by="PlayerFeedback state dodge; Krail's dodge move (swing_sfx)", **X)
add("dash", "sfx", 1, "Powerful forward dash burst: a charged electric thrust ignition, tight air rip and a short whooshing tail, cyberpunk energy boost, punchy." + TAIL,
    0.35, gen=1.0, mix_db=-10, used_by="PlayerFeedback state dash", **X)
add("respawn", "stinger", 1, "Reconstitution at a checkpoint: a soft rising electric hum that swells and resolves into a gentle warm chime, reactor heartbeat restarting, hopeful but restrained." + TAIL,
    0.9, gen=1.5, mix_db=-14, used_by="PlayerFeedback on player_respawned", **X)

# ---------------------------------------------------------------- player combat (existing)
add("slash", "sfx", 1, "Fast energy-blade sword slash: a thin sharp air swipe with a crackling electric edge hum, quick and light, no impact." + SHEET,
    0.22, gen=2.5, var=3, mode="sheet", pp="sfx_sheet_slice", mix_db=-12,
    used_by="pulse_blade, split_katars swing_sfx", notes="Whoosh layer only; impact is 'hit'. Pilot slash exists (pilot/slash.wav) and can seed variation 1.", **X)
add("slash_heavy", "sfx", 1, "Heavy two-handed energy-blade swing: deep wide air swoosh, a charged electric roar building through the arc, weighty, no impact." + SHEET,
    0.4, gen=2.5, var=2, mode="sheet", pp="sfx_sheet_slice", mix_db=-10,
    used_by="pulse_blade/split_katars heavy swing_sfx", **X)
add("hit", "sfx", 1, "Blade hit confirm on an armoured android: crisp metallic flesh-and-plate impact, a bright electric spark crack, tight and punchy, very short." + SHEET,
    0.18, gen=2.0, var=3, mode="sheet", pp="sfx_sheet_slice", mix_db=-7,
    used_by="player hit_sfx (light), scattergun/pistol hit", notes="The most important sound in the game: transient first 10 ms must cut through music. Layer rule: whoosh(slash) + hit + optional spark tail.", **X)
add("hit_heavy", "sfx", 1, "Heavy crushing hit on an armoured machine body: deep metal crunch, low boom, electric discharge crackle tail, powerful and satisfying." + SHEET,
    0.4, gen=2.5, var=2, mode="sheet", pp="sfx_sheet_slice", mix_db=-5,
    used_by="heavy hit_sfx, hazard/impact/grid_clamp attacks, revolver", **X)
add("block", "sfx", 1, "Attack blocked by an energy guard: a hard bright metallic clang with a glassy electric shield ring, short deflect ping." + SHEET,
    0.3, gen=2.0, var=2, mode="sheet", pp="sfx_sheet_slice", mix_db=-9,
    used_by="PlayerCombat blocked, BreakableWall (too weak), ScannerBeam", notes="Guard colour #7fd7ff has a sound: glassy ring. Keep distinct from hit.", **X)
add("shoot_pistol", "sfx", 1, "Compact sci-fi service pistol shot: tight snappy electric-kinetic crack, short mechanical slide click, small room slap, no long echo." + SHEET,
    0.3, gen=2.0, var=2, mode="sheet", pp="sfx_sheet_slice", mix_db=-10, used_by="service_pistol fire_sfx", **X)
add("shoot_scatter", "sfx", 1, "Sci-fi scattergun blast: wide heavy spread shot with a thick boom, rattling pellets of energy, pump-like mechanical clack after." + TAIL,
    0.55, gen=1.0, mix_db=-7, used_by="scattergun fire_sfx", **X)
add("shoot_revolver", "sfx", 1, "Heavy magnum revolver shot with a charged energy round: loud deep crack, heavy low thump, metallic ring and short concrete-alley echo tail." + TAIL,
    0.7, gen=1.2, mix_db=-7, used_by="heavy_revolver fire_sfx", **X)
add("empty", "sfx", 1, "Dry fire click of an empty gun: a small light metallic trigger click with a tiny electronic denial blip." + TAIL,
    0.12, gen=1.0, mix_db=-16, used_by="PlayerCombat no ammo; ShopMenu/LoadoutMenu refusal", notes="Shared gun/menu refusal: plays on SFX bus (id has no ui_ prefix).", **X)
add("reload", "sfx", 1, "Quick gun reload: magazine slides out and clicks in, slide racked, crisp small mechanical metal clicks." + TAIL,
    0.45, gen=1.0, mix_db=-15, used_by="PlayerCombat reload", **X)
add("heal_start", "sfx", 1, "Beginning to channel healing energy: a soft low electric hum starting to rise, gentle breathy energy intake." + TAIL,
    0.4, gen=1.0, mix_db=-15, used_by="HealState enter", **X)
add("heal", "stinger", 1, "Healing completed: a warm rising shimmer of soft bioelectric light, gentle crystalline chime, soothing resolution." + TAIL,
    0.6, gen=1.0, mix_db=-11, used_by="PlayerCombat heal", notes="Healing green #7dff9a has a sound: warm upward chime; nothing else uses this interval.", **X)
add("player_hurt", "sfx", 1, "Player takes damage: a sharp painful electric zap and body impact thud, reactor glitch stutter, short distorted crunch." + SHEET,
    0.35, gen=2.0, var=2, mode="sheet", pp="sfx_sheet_slice", mix_db=-5,
    used_by="PlayerCombat hurt", notes="Must be unmistakable vs 'hit' (player vs enemy): lower, distorted, glitchy. Pair with a 250 ms music low-pass dip (code change 6).", **X)
add("perfect_dodge", "stinger", 1, "Perfect dodge time-slow flourish: a crisp reverse whoosh into a bright crystalline ring with a deep sub drop, time freezing for a moment, elegant." + TAIL,
    0.7, gen=1.2, mix_db=-9, used_by="PlayerCombat perfect dodge", **X)
add("heartbeat", "sfx", 1, "Single heavy mechanical-organic heartbeat: deep low double thump lub-dub with a faint electric pulse, muffled, close." + TAIL,
    0.45, gen=1.0, mix_db=-7, used_by="ReactorCore critical (cooldown 0.2)", notes="Critical reactor cue; MusicDirector already ducks music 7 dB. Low end only, never masks telegraphs.", **X)
add("burnout", "sfx", 1, "Reactor burnout: an overloaded electric core shorting out with a sputtering crackle, a descending power-down whine and a hiss of steam." + TAIL,
    0.9, gen=1.5, mix_db=-8, used_by="ReactorCore burnout", **X)
add("rank_up", "sfx", 1, "Style rank up: a short punchy rising synth chime with an electric sparkle, rhythmic and confident, arcade-like but tasteful." + TAIL,
    0.4, gen=1.0, mix_db=-15, used_by="PlayerStyle rank up", **X)

# ---------------------------------------------------------------- enemies & bosses (existing)
add("enemy_telegraph", "sfx", 1, "Enemy attack warning: a sharp rising metallic glint and a short charging electric whine, piercing and clear, a split-second tell." + SHEET,
    0.3, gen=2.0, var=2, mode="sheet", pp="sfx_sheet_slice", mix_db=-10,
    used_by="Enemy telegraph, CeilingTracker lock", notes="Danger red #ff3b4f has a sound: rising glint 1-3 kHz. Highest mix priority after player_hurt; music and ambience must leave 1-3 kHz room.", **X)
add("enemy_attack", "sfx", 1, "Android enemy melee strike: a fast mechanical servo swing whoosh with a sharp metal blade swish, aggressive." + SHEET,
    0.3, gen=2.0, var=2, mode="sheet", pp="sfx_sheet_slice", mix_db=-12,
    used_by="enemy swing_sfx (28 attack defs)", **X)
add("enemy_shoot", "sfx", 1, "Hostile drone fires an energy bolt: a buzzy electric zap launch with a thin pew, slightly hollow and synthetic." + SHEET,
    0.3, gen=2.0, var=2, mode="sheet", pp="sfx_sheet_slice", mix_db=-12,
    used_by="drone/watcher/Krail/Collector swing_sfx", **X)
add("enemy_die", "sfx", 1, "Android enemy destroyed: a crunching metal break, electric short-circuit burst, sparks and small parts clattering, powering down whine." + SHEET,
    0.8, gen=3.0, var=2, mode="sheet", pp="sfx_sheet_slice", mix_db=-8,
    used_by="Enemy die", **X)
add("boss_roar", "stinger", 1, "Huge security machine boss roar: a distorted mechanical howl made of grinding servos, a siren wail and a deep electrical growl, menacing, with a long metallic reverb tail." + TAIL,
    1.8, gen=2.5, mix_db=-5, used_by="BossArena start, Collector/Krail behaviours, ChaseDirector", notes="P2 splits into boss_roar_collector / boss_roar_krail (code change 7).", **X)
add("boss_slam", "sfx", 1, "Massive heavy industrial press slam: a gigantic metal impact on concrete, deep sub boom, debris and chains rattling, short rumble tail." + TAIL,
    1.0, gen=1.5, mix_db=-4, used_by="Collector drop press, Krail slam, GridClamp, ChaseDirector", **X)

# ---------------------------------------------------------------- world & progression (existing)
add("anchor", "stinger", 1, "Activating a checkpoint beacon: a deep resonant electric bell tone blooming open, a warm reactor hum that settles into calm, sacred and safe." + TAIL,
    1.6, gen=2.5, mix_db=-9, used_by="Anchor activate", notes="HK bench equivalent: the calmest, warmest sound in the game.", **X)
add("scrap_pickup", "sfx", 1, "Tiny metal scrap pickup: a small bright tinkling of metal bits collected with a soft magnetic zip." + SHEET,
    0.15, gen=2.0, var=3, mode="sheet", pp="sfx_sheet_slice", mix_db=-20,
    used_by="ScrapPickup", notes="Fires in bursts; random pitch +/-8% plus 3 variations; cooldown 0.03 stays.", **X)
add("scrap_recover", "stinger", 1, "Recovering a lost cache of scrap: a flurry of metal pieces magnetically pulled together with a rising whoosh and a satisfying clink." + TAIL,
    0.9, gen=1.5, mix_db=-11, used_by="ScrapCache", **X)
add("collect", "stinger", 1, "Collectible found: a delicate music-box-like glassy chime with a soft electric shimmer, curious and rewarding." + TAIL,
    0.9, gen=1.5, mix_db=-11, used_by="Collectible", **X)
add("wall_break", "sfx", 1, "Breakable concrete wall shattering: chunks of concrete and rebar crumbling, dust pouring, heavy debris falling." + TAIL,
    1.0, gen=1.5, mix_db=-6, used_by="BreakableWall broken", notes="Secret walls additionally play secret_found (new).", **X)
add("repeater", "sfx", 1, "Old signal repeater or breaker switched on: a heavy electrical relay clunk, a buzzing surge of current, radio tone locking in." + TAIL,
    0.9, gen=1.5, mix_db=-10, used_by="SignalRepeater, Breaker", **X)
add("gate", "sfx", 1, "Heavy industrial shutter door moving: a big metal gate grinding on rails with a hydraulic hiss and a final clank." + TAIL,
    1.0, gen=1.5, mix_db=-10, used_by="Gate, PowerShutter, CeilingTracker, FlagSwitch", **X)
add("quest_complete", "stinger", 1, "Quest completed: a short warm uplifting three-note motif on muted electric piano with a soft tape-warm synth pad, noir, resolving." + TAIL,
    1.8, gen=2.0, mix_db=-10, used_by="QuestTracker", **X)
add("ability_unlock", "stinger", 1, "Acquiring a powerful new ability: a deep rising surge of electric energy, a choir-like synth swell and a resonant metallic ring, triumphant yet mysterious." + TAIL,
    2.5, gen=3.0, mix_db=-7, used_by="AbilityPickup, WeaponPickup", **X)
add("purchase", "ui", 1, "Buying an item at a scrap shop: a satisfying mechanical cash register-like clack of metal tokens with a small bright confirm chime." + TAIL,
    0.4, gen=1.0, mix_db=-12, used_by="ShopMenu", notes="Plays on SFX bus today (no ui_ prefix): keep id, fine.", **X)
add("radio_static", "sfx", 1, "Old handheld radio tuning: a short burst of crackling analog static with a faint squelch and whistle, no voices." + TAIL,
    0.6, gen=1.0, mix_db=-16, used_by="act1_close, ending_redline sequences; memory beats", **X)
add("achievement", "ui", 1, "Achievement unlocked: an elegant short bright two-note chime with a soft sparkling tail, understated." + TAIL,
    0.9, gen=1.2, mix_db=-12, used_by="AchievementToast (UI bus)", **X)
add("ui_tick", "ui", 1, "Very soft short menu cursor tick: a tiny muted mechanical click like a quality switch, subtle and clean." + SHEET,
    0.05, gen=2.0, var=3, mode="sheet", pp="ui_sheet_slice", mix_db=-18,
    used_by="menus, dialogue, memory player, scanner/shutter countdown", notes="Also the shutter countdown tick in world: keep it neutral.", **X)

# ---------------------------------------------------------------- memory (existing)
add("memory_open", "stinger", 1, "Entering a memory: a slow reversed piano note swelling into a soft underwater shimmer, distant muffled rain, dreamlike and melancholic." + TAIL,
    2.0, gen=2.5, mix_db=-10, used_by="MemoryScenePlayer open", **X)
add("memory_beat", "sfx", 1, "Soft memory fragment pulse: a single gentle muffled piano key with a faint glassy halo, quiet." + TAIL,
    0.5, gen=1.0, mix_db=-16, used_by="MemoryScenePlayer beat", **X)
add("memory_tear", "sfx", 1, "Memory tearing apart: a tape stretching and ripping, a glitchy distorted rewind and a descending digital crackle." + TAIL,
    0.8, gen=1.2, mix_db=-12, used_by="MemoryScenePlayer tear", **X)
add("memory_detail", "stinger", 1, "Noticing a hidden detail in a memory: a high delicate crystalline bell with a slow shimmering tail, intimate and quiet." + TAIL,
    1.2, gen=1.5, mix_db=-13, used_by="MemoryScenePlayer detail", **X)

# ================================================================ NEW ids
# footsteps (code change 3)
add("footstep_concrete", "footstep", 1, "Footsteps of one light-footed runner in rubber-soled boots on wet gritty concrete, individual steps, soft heel-toe, slight damp scuff." + SHEET,
    0.14, gen=3.0, var=3, mode="sheet", mix_db=-20, used_by="new PlayerFootsteps (run state), Undercity/Lowlight default surface")
add("footstep_metal", "footstep", 1, "Footsteps of one light runner in boots on a hollow steel catwalk grate, individual steps, light metallic ring and rattle." + SHEET,
    0.16, gen=3.0, var=3, mode="sheet", mix_db=-21, used_by="catwalks, lifts, rails, one-way platforms")
add("footstep_water", "footstep", 1, "Footsteps of one runner splashing through ankle-deep puddle water on concrete, individual steps, small splashes." + SHEET,
    0.2, gen=3.0, var=3, mode="sheet", mix_db=-20, used_by="Flooded Alley, Undercity floors near seepage")
add("footstep_wood", "footstep", 2, "Footsteps of one light runner in boots on old creaky wooden planks, individual steps, soft hollow knock." + SHEET,
    0.15, gen=3.0, var=3, mode="sheet", mix_db=-20, used_by="Relay planks, Market stalls, Bell Tower crates")
add("land_water", "sfx", 2, "Landing in shallow water from a jump: a splash with boot thud and droplets." + TAIL,
    0.4, gen=1.0, mix_db=-10, used_by="PlayerFeedback land on water surface")
add("wall_slide_scrape", "sfx", 3, "Sliding down a concrete wall: glove and boot friction scrape, continuous." + LOOPT,
    1.5, gen=2.0, loop=True, mix_db=-18, used_by="future wall slide (Ironworks)")

# combat layers
add("hit_spark_tail", "sfx", 2, "Short electric spark crackle and fizzle, small arcs of current dying out." + SHEET,
    0.3, gen=2.0, var=2, mode="sheet", pp="sfx_sheet_slice", mix_db=-16, used_by="layer under hit on kill-blow or crit (code change 5)")
add("enemy_stagger", "sfx", 2, "Armoured android staggered: a heavy servo stutter, metal plates rattling and a glitchy power dip." + TAIL,
    0.6, gen=1.0, mix_db=-9, used_by="poise break (Shield guard break, GridClamp stun)")
add("enemy_alert", "sfx", 2, "Security android notices an intruder: a short two-tone electronic chirp and a servo head-turn whir." + TAIL,
    0.4, gen=1.0, mix_db=-14, used_by="Enemy aggro start")
add("drone_rotor_loop", "sfx", 3, "Small hovering security drone: a buzzing electric rotor hum, steady." + LOOPT,
    3.0, gen=4.0, loop=True, mix_db=-24, used_by="Scout Drone positional loop (AudioStreamPlayer2D)")
add("boss_defeat", "stinger", 1, "A giant machine boss collapses: a long overload whine, cascading explosions of sparks, huge metal body crashing down, then a settling hiss and silence." + TAIL,
    3.5, gen=4.0, mix_db=-5, used_by="EventBus.boss_defeated (MusicDirector goes AFTERMATH)")
add("boss_phase", "stinger", 2, "Boss enters an enraged second phase: a violent power surge, alarm sweep and a deep distorted machine scream." + TAIL,
    1.8, gen=2.0, mix_db=-6, used_by="boss phase change")
add("boss_roar_collector", "stinger", 3, "Hovering collector drone boss screech: a cold synthetic siren sweep and grinding hook chains, surgical and inhuman." + TAIL,
    1.6, gen=2.0, mix_db=-5, used_by="CollectorDroneBehavior (code change 7)")
add("boss_roar_krail", "stinger", 3, "Armoured warden enforcer boss battle cry through a voice modulator: a distorted mechanical bellow with riot-gear metal clatter, no words." + TAIL,
    1.6, gen=2.0, mix_db=-5, used_by="WardenKrailBehavior (code change 7)")

# discovery / world
add("secret_found", "stinger", 1, "A hidden passage revealed: a soft mysterious rising glassy shimmer with a deep resonant hum, curious and magical, understated." + TAIL,
    1.6, gen=2.0, mix_db=-10, used_by="BreakableWall with persist_id / secret rooms (code change 5)")
add("flow_enter", "sfx", 2, "Entering a high-energy zone: a fast rising electric whoosh and a pulse of reactor power spinning up." + TAIL,
    0.8, gen=1.2, mix_db=-13, used_by="FlowZone body_entered")
add("area_title", "stinger", 2, "District name reveal: a slow deep cinematic boom with a long dark metallic resonance, solemn, noir." + TAIL,
    3.0, gen=3.5, mix_db=-10, used_by="first entry into a district (title card)")
add("breaker_countdown", "sfx", 3, "Electric timer tick: a crisp relay click with a faint buzz, mechanical." + SHEET,
    0.12, gen=2.0, var=2, mode="sheet", pp="sfx_sheet_slice", mix_db=-16, used_by="PowerShutter countdown (replaces ui_tick in world)")
add("lift_loop", "sfx", 3, "Old industrial cargo lift moving: cables humming, motor whine, rattling cage." + LOOPT,
    4.0, gen=5.0, loop=True, mix_db=-18, used_by="Broken Lift / Bell Tower lifts")

# UI (code change 4)
add("ui_confirm", "ui", 1, "Menu confirm: a soft clean mechanical click with a small warm electric tone, pleasant and quiet." + TAIL,
    0.2, gen=1.0, mix_db=-15, used_by="MenuScreen accept")
add("ui_back", "ui", 1, "Menu back or cancel: a soft muted lower mechanical click with a tiny descending tone." + TAIL,
    0.2, gen=1.0, mix_db=-16, used_by="MenuScreen cancel/back")
add("ui_open", "ui", 2, "Pause menu opening: a smooth soft CRT power-on whoosh with a faint electric hum rising." + TAIL,
    0.5, gen=1.0, mix_db=-15, used_by="pause/map/journal open")
add("ui_close", "ui", 2, "Pause menu closing: a soft CRT power-down whoosh, descending hum." + TAIL,
    0.4, gen=1.0, mix_db=-16, used_by="pause/map/journal close")
add("ui_dialogue_blip", "ui", 2, "Soft short typewriter-like electronic text blip, very subtle." + SHEET,
    0.05, gen=2.0, var=3, mode="sheet", pp="ui_sheet_slice", mix_db=-24, used_by="SeqLine.blip / DialogueBox letters (blip ids are empty today)")
add("ui_title_start", "ui", 2, "Pressing start on a title screen: a deep soft boom and a rising electric swell into silence." + TAIL,
    1.5, gen=2.0, mix_db=-12, used_by="Title screen New Game/Continue")

# ---------------------------------------------------------------- ambience beds (code change 2)
add("amb_undercity_ward", "ambience", 1, "Abandoned flooded underground medical ward: slow irregular water drips into puddles, flickering fluorescent tube buzz, faint distant pump machinery, cold concrete room tone, eerie and quiet." + LOOPT,
    30.0, gen=30.0, loop=True, mix_db=-2, used_by="Wake, Medical Ruin, Broken Lift, Collector Bay (between fights)")
add("amb_undercity_shaft", "ambience", 2, "Deep underground maintenance shaft: rhythmic slow water pump thumps, pipes groaning, trickling water, low machinery drone." + LOOPT,
    30.0, gen=30.0, loop=True, mix_db=-2, used_by="Maintenance Shaft, First Pursuit")
add("amb_undercity_tunnel", "ambience", 2, "Long underground transit tunnel: hollow wind moving through, distant low rumble, sparse drips echoing far away." + LOOPT,
    30.0, gen=30.0, loop=True, mix_db=-2, used_by="Escape Tunnel")
add("amb_lowlight_street", "ambience", 1, "Rainy neon city alley at night: steady rain on wet concrete and metal awnings, gutters overflowing, distant city hum and far traffic, a faint neon sign buzz, noir." + LOOPT,
    30.0, gen=30.0, loop=True, mix_db=-1, used_by="Flooded Alley, Market Run, Smuggler Route exterior, Warden Tower yard")
add("amb_lowlight_interior", "ambience", 1, "Inside a run-down apartment block during heavy rain: muffled rain on the roof and windows, water dripping from ceilings, electrical hum, old building creaks." + LOOPT,
    30.0, gen=30.0, loop=True, mix_db=-2, used_by="Apartment Stack, Security Station, Power Block interior, Bell Tower inside")
add("amb_lowlight_roof", "ambience", 2, "Windy rainy rooftops of a megacity at night: gusting wind, rain sheets, flapping tarps, distant thunder rolls, far sirens." + LOOPT,
    30.0, gen=30.0, loop=True, mix_db=-2, used_by="Neon Roofs, Rainline Chase")
add("amb_lowlight_power", "ambience", 2, "Electrical substation room: a deep transformer hum at mains frequency, occasional small arc crackles, cooling fans." + LOOPT,
    20.0, gen=20.0, loop=True, mix_db=-3, used_by="Power Block (layer under interior bed)")
add("amb_relay_hub", "ambience", 1, "Cosy underground refuge settlement at night: warm sodium lamp hum, a small wood stove crackle, kettle, distant muffled conversation murmur without words, soft radio static far away, safe and warm." + LOOPT,
    30.0, gen=30.0, loop=True, mix_db=-2, used_by="The Relay")
add("amb_deeprig_void", "ambience", 3, "Sterile empty test chamber: a very low clean sub hum, faint high electrical whine, sparse soft ticks, vast and cold." + LOOPT,
    20.0, gen=20.0, loop=True, mix_db=-4, used_by="Deep Rig / Training Pit")
add("amb_drip", "ambience", 1, "Single water drops falling into a puddle in a concrete cave, echoing." + SHEET,
    0.6, gen=3.0, var=3, mode="sheet", pp="amb_oneshot_slice", mix_db=-18, used_by="AmbientEmitter random one-shots (Undercity, Lowlight interiors)")
add("amb_neon_buzz", "ambience", 2, "Faulty neon sign: electric buzz with irregular flicker crackles." + LOOPT,
    4.0, gen=5.0, loop=True, mix_db=-22, used_by="AudioStreamPlayer2D on NeonSign (broken signs flicker louder = secret hint)")
add("amb_thunder", "ambience", 2, "Distant thunder roll over a city, deep and long." + TAIL,
    5.0, gen=5.0, mix_db=-14, used_by="Lowlight random one-shot synced to the DistrictBackdrop lightning flash (flash reduction keeps sound)")
add("amb_pipe_groan", "ambience", 3, "Old metal pipes groaning and creaking under pressure, deep resonant." + TAIL,
    3.0, gen=3.0, mix_db=-18, used_by="Undercity random one-shot")
add("amb_train_pass", "ambience", 3, "Elevated train passing overhead at a distance, rumbling and rattling then fading." + TAIL,
    6.0, gen=6.0, mix_db=-14, used_by="Lowlight exterior rare one-shot")

# ---------------------------------------------------------------- music (code change 1)
M = " Instrumental only, no vocals. Seamlessly loopable: consistent energy start to end, no intro fade-in, no ending, no big finale."
add("mus_title", "music", 1, "Melancholic noir cyberpunk title theme, 96 BPM, A minor, chord cycle Am F Dm E. Lonely muted electric piano plays a slow falling motif A C B A F E D E over a warm tape-saturated analog synth pad and soft rain-like texture, distant felt piano, sparse, atmospheric, beautiful and sad." + M,
    90.0, gen=90.0, loop=True, pp="music_loop", mix_db=-2, used_by="State.TITLE")
add("mus_relay", "music", 1, "Warm intimate refuge theme in A minor, 96 BPM, chords Am F Dm E. Gentle fingerpicked nylon guitar and a soft harmonium drone, a little lo-fi tape warmth, crackle of an old radio, a hint of the falling motif A C B A, calm, safe, lived-in, hopeful but tired." + M,
    90.0, gen=90.0, loop=True, pp="music_loop", mix_db=-2, used_by="State.HUB (plus free-time hub extras for growth)")
add("mus_undercity_explore", "music", 1, "Dark ambient exploration music for a flooded underground medical complex, A minor, very slow, beatless. Low bowed cello drones, cold glassy synth textures, distant metallic resonances, a lonely celesta playing fragments of a falling motif A C B A, vast, eerie and melancholic, lots of space and silence." + M,
    90.0, gen=90.0, loop=True, pp="music_loop", mix_db=-2, used_by="State.EXPLORE and AFTERMATH in Undercity")
add("mus_lowlight_explore", "music", 1, "Rain-soaked noir city exploration music, A minor, 96 BPM, chords Am F Dm E. Muted trumpet and Rhodes electric piano playing a slow falling motif, warm analog synth pad, soft brushed hi-hat barely present, deep upright-like synth bass, melancholic neon night." + M,
    90.0, gen=90.0, loop=True, pp="music_loop", mix_db=-2, used_by="State.EXPLORE and AFTERMATH in Lowlight")
add("mus_flow", "music", 1, "Driving intense cyberpunk chase music, A minor, 128 BPM, chords Am F Dm E. Pulsing analog synth bass arpeggios, tight punchy breakbeat drums, urgent string ostinato, dark and propulsive, the falling motif A C B A F E D E on a gritty synth lead, relentless forward motion." + M,
    60.0, gen=60.0, loop=True, pp="music_loop", mix_db=-2, used_by="State.FLOW (all districts, P1); per-district in P2")
add("mus_boss", "music", 1, "Epic dark boss battle music, A minor, 140 BPM. Heavy distorted industrial drums, aggressive analog synth bass, dramatic low strings and brass stabs, choir-like synth pads, the falling motif A C B A F E D E as a menacing lead, relentless, climactic." + M,
    60.0, gen=60.0, loop=True, pp="music_loop", mix_db=-2, used_by="State.BOSS (Collector Drone, Warden Krail, Chase)")
add("mus_memory", "music", 2, "Fragile memory music, A minor, very slow and free-time. Solo felt piano with soft reverb, a faint music-box, distant muffled rain, tape wobble, tender and heartbreaking, the falling motif A C B A played slowly." + M,
    60.0, gen=60.0, loop=True, pp="music_loop", mix_db=-4, used_by="State.MEMORY")
add("mus_boss_krail", "music", 2, "Brutal authoritarian boss battle theme, A minor, 140 BPM. Marching industrial percussion, alarm-like synth brass, heavy distorted bass, riot-police menace, the falling motif A C B A F E D E twisted into a militant lead." + M,
    60.0, gen=60.0, loop=True, pp="music_loop", mix_db=-2, used_by="State.BOSS in Warden Tower")
add("mus_lowlight_flow", "music", 2, "Rain-drenched neon chase music, A minor, 128 BPM, chords Am F Dm E. Fast rolling synth bass, punchy drum machine with trap-like hats, muted trumpet stabs, Rhodes chords, the falling motif A C B A on a bright synth lead, urgent." + M,
    60.0, gen=60.0, loop=True, pp="music_loop", mix_db=-2, used_by="State.FLOW in Lowlight")
add("mus_relay_extras", "music", 3, "Free-time sparse solo harmonica and hummed-like synth phrases in A minor, no rhythm, no beat, long pauses between phrases, lonely campfire mood." + M,
    60.0, gen=60.0, loop=True, pp="music_loop", mix_db=-8, used_by="HUB growth layer 'lead' (arrhythmic, needs no sync)")
add("mus_ending", "music", 3, "Bittersweet closing theme, A minor resolving to A major, 80 BPM. Piano, strings and warm synth pad develop the falling motif A C B A F E D E into a hopeful rising line, cinematic, emotional." + " Instrumental only, no vocals.",
    90.0, gen=90.0, loop=False, pp="music_oneshot", mix_db=-2, used_by="ending_* sequences / credits")


def bank_ids():
    t = BANK.read_text()
    return re.findall(r'^id = &"([a-z_]+)"', t, re.M)


def main():
    ids = [e["id"] for e in E]
    assert len(ids) == len(set(ids)), "duplicate ids"
    bank = bank_ids()
    missing = [i for i in bank if i not in ids]
    flagged_existing = {e["id"] for e in E if e["existing_id"]}
    wrong = sorted(flagged_existing ^ set(bank))
    for e in E:
        assert 1 <= e["variations"] <= 3
    OUT.write_text(json.dumps(E, indent=1, ensure_ascii=False) + "\n")
    tot = {}
    for e in E:
        tot.setdefault(e["priority"], [0, 0])
        tot[e["priority"]][0] += e["est_credits"]
        tot[e["priority"]][1] += 1
    print(f"entries {len(E)}  bank ids {len(bank)}  missing {missing}  existing-flag mismatch {wrong}")
    for p in sorted(tot):
        print(f"P{p}: {tot[p][1]} entries, ~{tot[p][0]} credits")
    p1 = [e for e in E if e["priority"] == 1]
    by = {}
    for e in p1:
        by[e["category"]] = by.get(e["category"], 0) + e["est_credits"]
    print("P1 by category:", by)
    if "--check" in sys.argv and (missing or wrong):
        sys.exit(1)


if __name__ == "__main__":
    main()
