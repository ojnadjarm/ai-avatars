class_name A2ATypes
extends RefCounted
## Pure data shapes for Google's Agent2Agent (A2A) protocol — v1.0.
## Spec: https://a2a-protocol.org/latest/specification/
##
## This file contains NO behavior. Every function returns a Dictionary
## matching the JSON shape the spec defines, so payloads built in-process
## are byte-identical to what an HTTP-wrapped agent would put on the wire.
## When we later swap the in-process router for real HTTP, nothing in this
## file changes — the router serializes these dictionaries to JSON as-is.


# ── Task states ───────────────────────────────────────────────────────────
# Straight from the A2A spec. A Task's status.state is one of these.
const STATE_SUBMITTED      := "submitted"
const STATE_WORKING        := "working"
const STATE_INPUT_REQUIRED := "input-required"
const STATE_AUTH_REQUIRED  := "auth-required"
const STATE_COMPLETED      := "completed"
const STATE_FAILED         := "failed"
const STATE_CANCELED       := "canceled"
const STATE_REJECTED       := "rejected"

# ── Part kinds ────────────────────────────────────────────────────────────
const PART_TEXT := "text"
const PART_DATA := "data"
const PART_FILE := "file"

# ── Message roles ─────────────────────────────────────────────────────────
# Role is from the sender's perspective on the task.
const ROLE_USER  := "user"
const ROLE_AGENT := "agent"


# ── Parts ─────────────────────────────────────────────────────────────────

static func text_part(text: String) -> Dictionary:
	return {"kind": PART_TEXT, "text": text}


static func data_part(data: Dictionary) -> Dictionary:
	return {"kind": PART_DATA, "data": data}


# ── Message ───────────────────────────────────────────────────────────────

static func message(role: String, parts: Array, context_id: String = "", task_id: String = "") -> Dictionary:
	var msg := {
		"role": role,
		"messageId": new_message_id(),
		"parts": parts,
	}
	if context_id != "":
		msg["contextId"] = context_id
	if task_id != "":
		msg["taskId"] = task_id
	return msg


# ── Task ──────────────────────────────────────────────────────────────────

static func task(id: String, context_id: String, state: String, history: Array, artifacts: Array) -> Dictionary:
	return {
		"id": id,
		"contextId": context_id,
		"status": {"state": state},
		"history": history,
		"artifacts": artifacts,
	}


# ── Artifact ──────────────────────────────────────────────────────────────

static func artifact(id: String, name: String, parts: Array) -> Dictionary:
	return {"id": id, "name": name, "parts": parts}


# ── JSON-RPC envelopes ────────────────────────────────────────────────────

static func rpc_request(id: String, method: String, params: Dictionary) -> Dictionary:
	return {
		"jsonrpc": "2.0",
		"id": id,
		"method": method,
		"params": params,
	}


static func rpc_result(id: String, result: Dictionary) -> Dictionary:
	return {
		"jsonrpc": "2.0",
		"id": id,
		"result": result,
	}


static func rpc_error(id: String, code: int, message: String) -> Dictionary:
	return {
		"jsonrpc": "2.0",
		"id": id,
		"error": {"code": code, "message": message},
	}


# ── Id generators ─────────────────────────────────────────────────────────
# Short random hex strings — not strictly UUIDs, but unique enough for
# in-process use and compact in logs. If we ever expose these over the
# wire we can switch to real UUIDs with no caller change.

static func new_message_id() -> String:
	return "msg-" + _rand_hex(12)

static func new_task_id() -> String:
	return "task-" + _rand_hex(12)

static func new_context_id() -> String:
	return "ctx-" + _rand_hex(12)


static func _rand_hex(length: int) -> String:
	const HEX := "0123456789abcdef"
	var out := ""
	for i in length:
		out += HEX[randi() % 16]
	return out
