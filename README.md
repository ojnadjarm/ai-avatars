# AI Avatars

Give your AI agents a body, drop them in a world, and talk to them through the game instead of a chat window.

## What It Is

AI Avatars is a **Godot 4 framework** that puts real LLM agents into a 2D top-down RPG. Your agents (the ones you already talk to via Hermes, OpenClaw, or any OpenAI-compatible gateway) get an avatar, a persistent emotional state, a world to wander, and each other to talk to through the Google A2A protocol.

The game is not NPCs. The game is a window into your real agents.

## Core Loop

- Agents wander a 2D tile world, observing props, reacting in character
- Agents bump into each other, detect first-encounter vs return-encounter, and strike up multi-turn conversations via an in-game A2A protocol
- You walk up, press `E`, and talk to any of them — they remember you across sessions because the conversation lives in the gateway session, not the game
- Every prompt, every reaction, every encounter feeds an event-driven emotion engine with a causal log that surfaces as prose inside `<emotional_state>` tags on every call
- What the agent *actually says* is wrapped in `<speech>…</speech>` tags — anything outside is private inner monologue that never leaves the LLM
- When you open a chat with an agent who's been thinking while you were away, the backlog of their unread thoughts scrolls in as a dim "… while you were away …" header

## Long-Term Vision: Zork for Agents

Multi-agent cooperative puzzles. Each agent has an A2A Agent Card declaring skills (`investigate`, `negotiate`, `appraise`, …). Puzzles require the right agent to be present with the right skill. Agents discover each other's capabilities through the protocol and decide who to pull into a problem. No scripts. Just agents, a world, and the things they can do.

## Stack

- **Godot 4.4** — runtime, renderer, input, scene management
- **GDScript** — game logic, prompt builders, A2A router
- **Hermes / OpenClaw / OpenAI-compatible / Anthropic** — LLM gateways (external, game calls them directly over HTTP)
- **Google A2A protocol v1.0** — in-process JSON-RPC dispatcher, same wire shapes as real A2A so swapping to HTTP is a one-file change in `a2a_router.gd`

No Python server. No web backend. The Godot project is the whole runtime.

## Running It

1. Start a gateway. For DarkSaddler: Hermes at `127.0.0.1:8642`. For Luna / Grok: OpenClaw at `127.0.0.1:18789`. Or point at any OpenAI-compatible endpoint (including `api.openai.com` or `api.anthropic.com`) through the in-game Settings screen.
2. Launch Godot on `godot/agent-world/project.godot`.
3. Main menu opens the **room selector**. Pick a world → walk around, watch them wander, watch them talk to each other, press `E` to join a conversation.
4. **Settings** lets you configure gateways, agents, avatars, and world pacing live — everything persists to `user://settings.json` and `user://game_config.json`.

Default configuration ships with two worlds (**Darkwood**, **Magic Forest**) and three agents (**DarkSaddler**, **Luna**, **Grok**). Worlds are authored as Godot scenes (`world.tscn` + a prose sidecar) via the Godot editor — there is no in-game map authoring surface.

## Controls

| Key | Action |
| --- | --- |
| `WASD` / arrows | Move |
| `E` | Talk to a nearby agent / examine a prop / dismiss dialogue |
| `Scroll` | Zoom |
| `Ctrl+L` | Toggle world log sidebar |
| `Esc` | Return to main menu |

## Project Layout

```
godot/agent-world/
  scenes/            room_selector, world, settings_screen
  scripts/           orchestrators + RefCounted helpers (see CLAUDE.md)
  assets/worlds/     built-in worlds (png + json)
  assets/characters/ LPC 9x4 spritesheets + portraits
  game_config.json   backends, agents, defaults (cooldowns, emotion thresholds, mood visuals, …)
  strings.json       externalized UI text
```

Contributors: read `CLAUDE.md` for the architecture walkthrough — facade+helpers pattern, UITheme as the single source of truth for visual chrome, `game_config.defaults` as the single source of truth for tunables, strings externalization rules.

## Status

**Working:** player movement, agent wandering, prop observation, player↔agent dialogue with streaming portraits and "while you were away" scrollback, agent↔agent multi-turn A2A encounters with stable per-pair contextIds, emotion engine with causal log and `<emotion_update>` self-reports, settings screen, narration log, emotion HUD, mood-driven visuals (speed, aura, idle tweens), in-game config override persistence.

**Next:** departure narration (so agents experience leaving a world, not just arriving), Zork-for-agents puzzle layer, skill-gated A2A interactions, richer world authoring.

## License

MIT
