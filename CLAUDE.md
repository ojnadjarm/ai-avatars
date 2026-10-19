# CLAUDE.md

Guidance for Claude Code when working in this repo.

## Project Purpose

AI Avatars is a Godot 4 framework that puts real LLM agents into a 2D top-down RPG as a visual interface to the agents you already use. Each agent has a persistent emotional state, a body that moves through the world, and talks to other agents via an in-game A2A protocol. Long-term vision: "Zork for agents" — multi-agent puzzles solved cooperatively through skill-gated capabilities.

## Runtime

The Godot project at `godot/agent-world/` **is the runtime**. There is no Python server. Godot talks directly to local gateways:

- **Hermes** gateway at `http://127.0.0.1:8642` (DarkSaddler)
- **OpenClaw** gateway at `http://127.0.0.1:18789` (Luna, Grok)

Backends and agents are configured in `godot/agent-world/game_config.json`. Per-agent session IDs live inside each gateway's state (Hermes SQLite, OpenClaw session store), so conversation history is authoritative on the gateway side — the game does not duplicate it.

## Commands

```bash
# Launch the game (WSL2)
godot
```

## Entry Flow

Main scene is `scenes/room_selector.tscn` → user picks a world → `scenes/world.tscn` (driven by `world_loader.gd`). `scenes/settings_screen.tscn` is the config UI.

## Architecture (Godot-side)

Autoloads (`project.godot`): `GameState` (config + user settings), `Strings` (externalized UI text), `McpServer` (runtime MCP server — see "MCP transport" below).

### Runtime orchestrators (Node2D scripts attached to scenes)

- **`world_loader.gd`** — the world scene. Owns `config`, `room_bounds`, `llm`, `activity_gate`, `llm_request_queue`, `encounter_dispatcher`, containers for agents/props, and every UI CanvasLayer. Delegates construction and I/O to the helpers below. Everyone else (agents, dialogue, routers) holds a reference to this Node as their "world context" — its public surface (`config`, `find_agent`, `request_agent_*`, `activity_gate`, etc.) must stay stable.
- **`settings_screen.gd`** — thin shell for the settings UI. Composes tabs, orchestrates save.
- **`room_selector.gd`** — main menu world picker.
- **`player.gd`** — player CharacterBody2D.

### World helpers (RefCounted, constructed by `world_loader`)

- **`world_builder.gd`** — stateless `static func`s: `build_background`, `build_boundaries`, `build_props`, `build_audio`.
- **`agent_spawner.gd`** — `spawn_all` + `find(id)`. Holds deps (container, player, props, display height, config).
- **`llm_coordinator.gd`** — `request_arrive`, `request_observe`, `request_talk`, response handlers. Holds a `world_loader` ref and reaches through it for `llm`, `activity_gate`, `narration_log`, `dialogue`.
- **`encounter_dispatcher.gd`** — multi-turn A2A flow between two agents. Owns the `A2ARouter`.
- **`a2a_router.gd`** — in-process A2A dispatcher using `inproc://<agent_id>` URLs.
- **`meeting_orchestrator.gd`** — group conversation orchestrator (player + N agents). Owned by `world_loader`. Accepts user messages via `submit_user_message`, fans each message to all attendees in randomised order per round using a delta-tracking transcript (`_seen_index` per attendee so no turn is replayed). On `end()` fires a fire-and-forget closing prompt to each attendee that was prompted at least once. Spatial gathering is handled upstream by `world_loader`; this class owns only the conversation layer.
- **`activity_gate.gd`** — **the** global "one action at a time" throttle for observations and A2A encounters. `can_trigger()` returns true when `remaining <= 0`. `trigger()` reseeds `remaining` to `cooldown_time` (`activity_global_cooldown`, default 30s) — callers call it when an action starts. `set_initial_delay(seconds)` is used once by `world_loader._ready` to seed the startup grace period. Ticked from `world_loader._process` via `tick(delta)`. Arrivals and player-initiated chat **do not** interact with the gate.
- **`llm_request_queue.gd`** — opaque-id queue for in-flight LLM requests.

### Runtime MCP server (autoload `McpServer`)

- **`mcp_server.gd`** — `Node` autoload. `TCPServer` polled from `_process`; gateways connect as MCP clients at `POST /mcp/<agent_id>` (`defaults.mcp.port`, 8975). `world_loader` calls `bind_world(self)`/`unbind_world()` so a `tools/call` with no world bound (e.g. curl from the room selector) answers nothing-happens narration instead of touching a nonexistent resolver. Routes verb actions through the same `world_loader.submit_agent_action()` facade the XML path uses; actions resolve immediately and the HTTP response is written in-line. `emotion_update` is a sixth tool, always resolved directly, mirroring `EmotionTags._apply_block`.
- **`mcp_protocol.gd`** — `class_name McpProtocol`, pure `static`, zero autoload/socket dependencies (unit-testable without opening a port). HTTP request framing (`feed_bytes`/`try_parse_http_request`), JSON-RPC dispatch (`initialize`/`ping`/`tools/list`/`tools/call`), the diegetic tool-name → canonical-verb map, and HTTP response building all live here; `mcp_server.gd` owns every socket/world concern instead.

### Settings helpers (RefCounted, composed by `settings_screen`)

- **`settings_form.gd`** — static form primitives: `text_row`, `option_row`, `check_row`, `number_row`, `range_row`, `form_label`, `section_header`, `parse_float`.
- **`settings_tab_player.gd`** — avatar grid + content paths. `build(parent)` / `commit()`.
- **`settings_tab_gateways.gd`** — gateway CRUD with type-specific placeholder hints.
- **`settings_tab_agents.gd`** — per-agent panels + avatar picker. `commit()` returns the rebuilt agents dict.
- **`settings_tab_world.gd`** — `activity_global_cooldown` (**sole** throttle on agent activity; there are no per-agent observation/encounter timers to configure) + `gateway_health_interval_seconds`. `commit(defaults)` mutates the passed defaults dict for both fields, batching through the same Save-button flow as every other tab here.

### Agent + gameplay

- **`agent.gd`** — `CharacterBody2D`, state machine (`IDLE`/`WALKING`/`OBSERVING`/`TALKING`/`ENCOUNTERING`), proximity checks, RVO avoidance, Theta* grid pathfinding, stall/wedge recovery, summon + meeting modes. Behavior tuning (`move_speed`, `observe_radius`, `encounter_radius`, `activity_cooldown`, `idle_decay_interval`) loaded from `game_config.defaults` in `_load_defaults()`. No per-agent observation/encounter timers — the global `ActivityGate` is the sole throttle. The `interactions` flag gates **only** autonomous behavior (wandering toward peers/props, proximity observations, proximity encounters); arrivals and player-initiated chat always fire regardless, so every spawned agent knows its world. Movement texture in the executor: acceleration-limited **speed** (magnitude only — never smooth the velocity direction; a direction-smoothed agent orbits its waypoint forever because turning radius v²/accel exceeds the 6px arrival tolerance) and a two-radius arrival profile (`arrival_slow_radius` ramp with `arrival_speed_floor`, then the 6px snap). The wedge tracker only accrues while actual velocity < 50% of commanded speed (a wedge is "told to move, not moving") and restamps its anchor on every waypoint advance — both conditions are load-bearing; without them normal slow/short walks trip escape nudges that self-sustain forever. Ambient wander decisions live in `agent_wander.gd`; the tagged flag `_walk_is_wander` routes texture + arrival dwell only to wander walks (summon/meeting walks stay crisp).
- **`agent_wander.gd`** — `class_name AgentWander extends RefCounted`, the ambient wander brain (host-ref pattern, owned by `agent.gd`). Decides WHEN (heavy-tailed log-normal dwell, look-around glances during dwell), WHERE (utility-scored candidate pool: interest-weighted prop rings via `AgentMemory.get_prop_interest` — the formerly dormant "Formula 3" hook — social rings around peers, correlated-heading exploration, home anchor; scored `weight × interest × novelty × distance-falloff × crowd factor`, spatial recency penalty, mood bias from `defaults.wander.mood_bias`, optional per-agent `wander_personality` multipliers in `agents{}`; picked by top-k roulette, never argmax), and HOW (per-walk speed jitter, FastNoiseLite sway + speed surge on a shared noise line with per-agent offsets, occasional mid-walk change of mind). All tunables under `defaults.wander` with empty-safe fallbacks. Scoring/sampling primitives are pure statics — headless-tested in `tests/unit/movement/test_agent_wander.gd`.
- **`agent_memory.gd`** — `seen_entities`, `entity_interest`, `visited_locations`, `met_agents`, plus `last_world_id` / `last_world_name` (stamped on every real arrival, used by `llm_coordinator` to pick the arrival narration mode on next entry). Persists to `user://saves/`.
- **`agent_card.gd`** — A2A Agent Card builders.
- **`character_sprite.gd`** — LPC 9x4 spritesheet loader.
- **`prompt_builder.gd`** — centralized XML-wrapped prompt construction. Also hosts `is_silence()` and `extract_speech()`.
- **`emotion_engine.gd`** — event-driven state + derived mood + causal ring buffer. Thresholds from `defaults.emotion`.
- **`emotion_tags.gd`** — parses `<emotion_update>` blocks out of LLM replies and applies them.
- **`action_resolver.gd`** — puzzle-layer action execution engine (ADR-0001). Parses `<action verb="..." target="..." [on="..."]/>` tags from LLM replies — five verbs: `go_to`, `take`, `use_object`, `use_skill`, `call_agent`. `resolve(agent, action)` validates per-verb preconditions, matches puzzle rules from `assets/puzzles/*.json`, applies effects to `WorldState`, drives the 3-state solve machine (unsolved → solving → solved, with collaborator credit), and returns `{narration, state_changed}`. **Only the observe path resolves actions** (arrivals discard them; talk/A2A never resolve). Handler order is load-bearing: `EmotionTags.parse_and_apply` → action resolve → `extract_speech`. `call_agent` dispatches an A2A encounter through `world_loader` (checks `activity_gate.can_trigger()`). Four-tier nothing-happens fallback: puzzle `default_fail_narration` → world `nothing_happens_text` → `defaults.puzzle.nothing_happens.<verb>` → `defaults.puzzle.nothing_happens_text`.
- **`world_state.gd`** — authoritative game-side puzzle state per world: `objects`, `flags`, `inventory`, `puzzles` dicts (+ runtime-only `flag_writers`, `_fired_puzzles`). All mutation through typed accessors. Persists to `user://saves/world_state_<world_id>.json` with `schema_version: 1`; invalid ids and corrupt/missing saves return clean defaults. Starting inventory applied from agent config on load.
- **`prop_layers.gd`** — pure static `render_for_agent(prop, agent, world_state)`: assembles base prop description + every layer text whose gate passes (`skill` → `agent.has_skill`, `item` → inventory, `flag` → world flag; unknown kinds evaluate false, warned at `WorldState.load_for` time). Gate metadata never appears in output; empty result returns `defaults.puzzle.empty_prop_fallback`.
- **`prop.gd`** — `class_name Prop extends Area2D` with exported `prop_id` / `prop_name` / `prop_description`; the runtime prop node type agents and the player iterate.
- **`a2a_types.gd`** — pure data shapes for Google's A2A v1.0.
- **`llm_client.gd`** — HTTP client for Hermes / OpenClaw / OpenAI / Anthropic.

### UI

- **`ui_theme.gd`** — `class_name UITheme`. **Single source of truth for every visual constant** (palette, button styles, mood colors, marker/bound colors, narration log type colors, toast success green, label shadows). Also hosts shared builders: `framed_panel_style`, `wallpaper_background`, `primary_button`, `action_button`, `modal`, `small_menu_button`, `mode_button`, `section_spacer`, `paint_danger`, `attach_arcane_corners`. **No other file should declare inline `Color(...)` literals for UI chrome.**
- **`dialogue_cloud.gd`** — conversation panel + full-screen portrait.
- **`narration_log.gd`** — right-sidebar world event log (Ctrl+L).
- **`log_modal.gd`** — reusable full-screen scrollable log modal. Static `show_entries(parent, title, lines)` factory; `is_any_open()` for Esc priority coordination. Used for the expanded world log and per-agent causal log.
- **`arcane_corners.gd`** — `Control` overlay that procedurally draws four arcane corner glyphs on a panel. Attached via `UITheme.attach_arcane_corners(panel)`.
- **`gateway_health.gd`** — `Node` child of `world_loader`. Periodically pings each configured gateway's health endpoint and emits `health_changed(gateway_id, state)`. States: `ok` / `fail` / `unknown`. Interval from `defaults.gateway_health_interval_seconds`. Uses `use_threads=false` + short timeout per the WSL2 HTTP rule.
- **`action_prompt.gd`** — floating "[E] Talk / Examine" hint.
- **`thought_bubble.gd`** — world-space blink bubble above agents.
- **`controls_hint.gd`** — bottom-left keyboard hint cloud. **The primary surface for player keyboard commands** — new actions prefer a hint row here over a button in the left stack. Auto-sizes via `grow_horizontal/vertical` anchored to the bottom-left point.

### Game state

- **`game_state.gd`** — autoload. Owns `config`, `defaults`, `agents`, `gateways`, content folder paths, user settings (`user://settings.json`), config override persistence (`user://game_config.json`). Public helpers: `get_float`, `get_range`, `get_default`, `get_agent_gateway/session/model`, `resolve_world_asset`, `resolve_character_asset`, `scan_available_sprites`, `load_portrait_texture`, `load_agent_portrait_texture`, `make_portrait_rect`.
- **`strings.gd`** — autoload. Loads `strings.json`. `get_string(key, replacements)` with `{placeholder}` substitution.

## Architectural patterns (established during the 2026-04-14 cleanup)

- **Facade + helpers.** The two biggest scripts (`world_loader`, `settings_screen`) are Node2D/CanvasLayer orchestrators that hold state and expose a stable public surface. Construction, rendering, and subsystem logic live in RefCounted helpers that take a host reference (or are called statically). External callers never touch the helpers directly — they go through the orchestrator.
- **No hardcoded values.** Every tunable lives in `game_config.defaults` and is pulled via `GameState.get_float()` / `get_range()` / `get_default()`. `@export` defaults in scripts exist only as absolute fallbacks for missing config keys.
- **No inline colors.** All `Color(...)` literals for UI chrome live in `ui_theme.gd`. Adding new visuals means adding a constant there first.
- **Strings externalized.** User-facing text (including BBCode format templates with `{speaker}` placeholders) lives in `strings.json`. Only internal debug `print()` statements and prompt content stay in code.
- **Pixel aesthetic (Arcane Grimoire).** Font sizes snap to the `{16, 32, 48}` pixel grid — `UITheme.FONT_SIZE_BODY=32`, `FONT_SIZE_HUD=16`, `FONT_SIZE_SECTION=32`, `FONT_SIZE_TITLE=48`. No intermediate values (12/14/22 etc.) — they fall off the grid and render blurry. All corner radii are zero: `UITheme.CORNER=0`, `FRAMED_CORNER=0`, every `set_corner_radius_all(N)` call uses 0. **Exception:** `thought_bubble.gd` keeps its 12px rounded cloud — it's an organic speech bubble, not a box/button.
- **Left-stack menu is quiet, hint cloud is primary.** `UITheme.prominent_button` is a subtle pill (`CONTROLS_HINT_KEY_BG` + 1px soft purple border, TEXT_DIM label). The in-world left stack holds **only** the Main Menu button; other player actions surface through the bottom-left `controls_hint` cloud. New player actions prefer a hint row over a button.

### Agent Layer Stack
- **SOUL** — lives in the gateway (Hermes `SOUL.md`, OpenClaw workspace)
- **IDENTITY** — game-side display name, spawn, capabilities (→ A2A Agent Card)
- **EMOTIONS** — `emotion_engine.gd`, event-driven state machine with causal log
- **MEMORY** — gateway session owns conversation history; `agent_memory.gd` owns game-state flags (visited, met, interest)
- **TOOLS** — agent skills declared in Agent Cards, used for A2A capability gating

### Prompt System (`prompt_builder.gd`)
All LLM input is XML-wrapped. Vocabulary:
- `<narration>…</narration>` — world events (arrival, observation)
- `<USER.md_message>…</USER.md_message>` — the player talking to the agent
- `<agent_message><agent>name</agent>…</agent_message>` — another agent speaking
- `<speech>…</speech>` — agent output; only this is delivered as dialogue, the rest is private inner monologue
- `<emotional_state>…</emotional_state>` — emotion context injected into system
- `<emotion_update>…</emotion_update>` — agent self-reports emotion deltas
- `<action verb="..." target="..." [on="..."]/>` — agent world-action intent (puzzle layer). Parsed by `ActionResolver`, stripped from rendered dialogue by `extract_speech`. Authoring instructions injected **only into observe prompts** from `defaults.puzzle.action_tag_instructions`.

#### Arrival narration modes
`build_arrive(config, agent, opts)` produces one of four outcomes based on `opts.previous_world_name`, `opts.is_new`, and `opts.transition_override`:

1. **First ever launch** (`previous == ""`) — embodied intro: *"You have existed as an agent for a while now. New worlds have been crafted for agents like you to walk and explore, and you have chosen to step into one of them. You have joined {name}. {description}"*. Fourth-wall safe: no "game", no "simulation", no "player".
2. **Cross-world to unfamiliar** (`previous != ""`, `is_new`) — *"Wandering through {prev}, you find a path that leads somewhere new. You have joined {curr}, a world unfamiliar to you. {description}"*
3. **Cross-world to familiar** (`previous != ""`, `!is_new`) — *"Wandering through {prev}, you find a way back to {curr} — a world you have walked before."*
4. **Per-pair override** — if the current world's config declares `transitions[previous_world_id]`, that string replaces the entire narration verbatim. Used for correlated worlds (e.g. day↔night pairs like Magic Forest ↔ Darkwood — see `assets/worlds/*.json` for examples).

**Same-world re-entry is silent** — `llm_coordinator.request_arrive` short-circuits when `agent.memory.last_world_id == current_world_id`, so quitting and re-entering the same world produces no prompt. The session just resumes.

**There is no departure prompt.** When the player quits to the main menu or the game closes for any reason (graceful or crash), nothing is written to agent sessions. State continuity is carried forward through the gateway's own session store plus the `last_world_id` stamp on `agent_memory`; the next arrival picks the right narration mode from those two facts alone.

### A2A Protocol (in-game)
Full JSON-RPC shapes from the Google A2A spec, dispatched in-process via `a2a_router.gd` using `inproc://<agent_id>` URLs. Swapping to real HTTP later is a one-file change. Pairs of agents share a stable `contextId` so gateway sessions maintain continuity across encounters. Multi-turn encounters use `params.meta` flags (`mid_conversation`, `final_turn`) to vary listener framing across turns.

### MCP transport
Every agent world-action — an XML `<action>` tag parsed from an observe reply, or an MCP `tools/call` — routes through the same choke point: `world_loader.submit_agent_action(agent, action, source, on_result)` → `ActionResolver.resolve()`. Actions always execute immediately; there is no approval hold or hold policy of any kind. `ActionResolver` itself never knows which transport called it. The two transports differ only in how the result reaches the agent: XML gets the existing fire-and-forget `<narration>` session echo (`llm_coordinator._apply_action_result`); MCP results ride back **inside the `tools/call` HTTP response** instead (`mcp_server.gd._finish_puzzle_action`) — never both, since an MCP agent's own gateway already delivers the narration as the tool's return value.

**Coexistence** (`GameState.is_agent_mcp(agent_id)`): an agent is MCP-transport only when its `agents{}` entry has `"mcp": true` **and** the master switch `defaults.mcp.enabled` is on — either alone resolves to false (fail toward XML). For an MCP agent: `prompt_builder.build_observe` omits `action_tag_instructions` from the system prompt (nothing to teach — the agent acts via tools, not tags), and `llm_coordinator._resolve_action_from_response` early-returns on any `<action>` tag that survives into chat text anyway, so a habit-emitted tag is discarded rather than resolved a second time. MCP agents also get a longer HTTP chat timeout (`defaults.mcp.chat_timeout_seconds`, 120s, vs. the flat 15s every other agent keeps) — an MCP agent's turn can involve multiple tool round-trips before the gateway's own chat response returns, and 15s would kill a multi-tool-call turn as `[gateway unavailable]` first.

### Config
- `godot/agent-world/game_config.json` — backends, agents, defaults (single `activity_global_cooldown`, emotion thresholds, mood visuals, movement tuning)
- `godot/agent-world/strings.json` — UI strings
- `godot/agent-world/assets/puzzles/*.json` — puzzle rule files (match/require/effects/solve schema consumed by `action_resolver.gd`; demo: `demo_stargate.json`)
- `godot/agent-world/assets/worlds/*.json` — world configs. Optional `transitions` map keyed by source world id provides verbatim arrival narration overrides for correlated-world pairs. Example: `"transitions": { "magic_forest": "The light thins and fades around you…" }` in `darkwood.json` fires when an agent arrives in Darkwood from Magic Forest.

## Fourth Wall Rule
In-world agents never learn they are in "a game" or "a simulation," never learn the names of other agents via their USER.md, and are never told "the player" exists. They see narration, they see other agents speaking to them, and they react as themselves.
