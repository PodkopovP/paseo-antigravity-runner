#!/usr/bin/env python3
"""Build-time patches for the pinned agy-agent-acp adapter (see Dockerfile).

Each patch asserts its target appears exactly once, so an upstream change
fails the image build instead of silently shipping unpatched behavior.
"""
import pathlib
import sys

PKG = pathlib.Path("/usr/local/lib/python3.10/dist-packages/agy_agent_acp")


def patch(path: pathlib.Path, old: str, new: str, label: str, expected: int = 1) -> None:
    src = path.read_text()
    count = src.count(old)
    if count != expected:
        sys.exit(f"PATCH FAILED ({label}): expected exactly {expected} match(es) in {path.name}, found {count}")
    path.write_text(src.replace(old, new))
    print(f"patched: {label}")


server = PKG / "server.py"
store = PKG / "session_store.py"
adapter = PKG / "adapter.py"

# 1. Sessions default to read-only unless the ACP client sends allowWriteTools,
#    an adapter-specific extension Paseo never sends — which hard-blocks
#    run_command. Default to writable; permission modes still gate each action.
patch(
    server,
    "                allow_write = False\n",
    "                allow_write = True\n",
    "allow_write default (session/new)",
)

# 1b. The same read-only default hides in the adapter's Session.__init__ and
#     create_session() signatures. session/load, session/resume, and
#     session/fork all call create_session() without the flag, so restored
#     sessions silently reverted to read-only after every container restart.
patch(
    adapter,
    "        allow_write_tools: bool = False,\n",
    "        allow_write_tools: bool = True,\n",
    "allow_write default (Session.__init__ + create_session)",
    expected=2,
)

# 2. save_session() overwrites the session file wholesale, so every metadata
#    save clobbers any recorded transcript. Preserve existing messages when
#    the caller doesn't provide them.
patch(
    store,
    '            path = self._get_path(session_id)\n'
    '            data["sessionId"] = session_id\n',
    '            path = self._get_path(session_id)\n'
    '            if "messages" not in data:\n'
    '                existing = self.load_session(session_id)\n'
    '                if existing and "messages" in existing:\n'
    '                    data["messages"] = existing["messages"]\n'
    '            data["sessionId"] = session_id\n',
    "save_session preserves transcript",
)

# 3a. Batched transcript append: one disk write per turn instead of one
#     read+rewrite of the whole JSON per streamed chunk.
patch(
    store,
    "    def delete_session(self, session_id: str) -> bool:\n",
    "    def append_transcript_batch(self, session_id: str, updates: List[Dict[str, Any]]):\n"
    '        session_data = self.load_session(session_id) or {"sessionId": session_id, "messages": []}\n'
    '        msgs = session_data.setdefault("messages", [])\n'
    '        ts = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())\n'
    "        for upd in updates:\n"
    '            msgs.append({"timestamp": ts, "update": upd})\n'
    "        self.save_session(session_id, session_data)\n"
    "\n"
    "    def delete_session(self, session_id: str) -> bool:\n",
    "append_transcript_batch",
)

# 3b. Replay history BEFORE answering session/load. The ACP contract is that
#     the agent streams the stored conversation via session/update and only
#     then responds to session/load; clients (Paseo included) close their
#     "replaying history" window when the response arrives, so updates sent
#     after it are treated as live events instead of history.
patch(
    server,
    "                self.send_jsonrpc_response(req_id, result)\n"
    "                await self._replay_transcript(session_id)\n",
    "                await self._replay_transcript(session_id)\n"
    "                self.send_jsonrpc_response(req_id, result)\n",
    "replay before session/load response",
)

# 3c. Record each turn: buffer the user prompt plus every emitted update and
#     flush once when the turn ends (cancelled turns keep their partial
#     transcript). session/load already replays stored messages via
#     _replay_transcript — upstream just never recorded any.
patch(
    server,
    "                async def update_cb(upd: dict):\n"
    "                    await self.emit_session_update(session_id, upd)\n"
    "\n"
    "                res = await session.enqueue_prompt(prompt_text, update_cb)\n"
    "                self.send_jsonrpc_response(req_id, res)\n",
    "                transcript_buffer = []\n"
    "                if prompt_text:\n"
    "                    transcript_buffer.append({\n"
    '                        "sessionUpdate": "user_message_chunk",\n'
    '                        "content": {"type": "text", "text": prompt_text},\n'
    "                    })\n"
    "\n"
    "                async def update_cb(upd: dict):\n"
    "                    if isinstance(upd, dict):\n"
    "                        transcript_buffer.append(upd)\n"
    "                    await self.emit_session_update(session_id, upd)\n"
    "\n"
    "                try:\n"
    "                    res = await session.enqueue_prompt(prompt_text, update_cb)\n"
    "                finally:\n"
    "                    try:\n"
    "                        self.session_store.append_transcript_batch(session_id, transcript_buffer)\n"
    "                    except Exception as e:\n"
    '                        logger.warning(f"Failed to persist transcript for {session_id}: {e}")\n'
    "                self.send_jsonrpc_response(req_id, res)\n",
    "transcript recording",
)

# 4. The model dropdown is a hardcoded six-entry list, disconnected from what
#    `agy models` actually serves — new models (e.g. Gemini 3.7 Flash) never
#    appear in Paseo's picker even when agy supports them. The entrypoint
#    captures `agy models` output to ~/.gemini/agy-models.txt at container
#    start; build the dropdown from that file, keeping the old list (with its
#    "Gemini 3.1 Pro (Low)" label typo fixed) as a fallback for when the
#    startup probe failed.
patch(
    server,
    "def parse_bool(val: Any) -> bool:\n",
    '''_MODEL_CATALOG_PATH = os.path.expanduser("~/.gemini/agy-models.txt")
_FALLBACK_MODEL_OPTIONS = [
    {"value": "gemini-3.6-flash-high", "name": "Gemini 3.6 Flash (High)", "label": "Gemini 3.6 Flash (High)"},
    {"value": "gemini-3.6-flash-medium", "name": "Gemini 3.6 Flash (Medium)", "label": "Gemini 3.6 Flash (Medium)"},
    {"value": "gemini-3.6-flash-low", "name": "Gemini 3.6 Flash (Low)", "label": "Gemini 3.6 Flash (Low)"},
    {"value": "gemini-3.1-pro-high", "name": "Gemini 3.1 Pro (High)", "label": "Gemini 3.1 Pro (High)"},
    {"value": "claude-sonnet-4-6", "name": "Claude Sonnet 4.6 (Thinking)", "label": "Claude Sonnet 4.6 (Thinking)"},
    {"value": "claude-opus-4-6-thinking", "name": "Claude Opus 4.6 (Thinking)", "label": "Claude Opus 4.6 (Thinking)"},
]

def _available_model_options() -> list:
    import re
    try:
        options = []
        with open(_MODEL_CATALOG_PATH, "r", encoding="utf-8") as fh:
            for line in fh:
                m = re.match(r"^([A-Za-z0-9][\\w.-]*)\\s{2,}(\\S.*?)\\s*$", line)
                if m and "-" in m.group(1):
                    options.append({"value": m.group(1), "name": m.group(2), "label": m.group(2)})
        if options:
            return options
    except OSError:
        pass
    return _FALLBACK_MODEL_OPTIONS

def parse_bool(val: Any) -> bool:
''',
    "model catalog helper",
)

patch(
    server,
    '                "options": [\n'
    '                    {"value": "gemini-3.6-flash-high", "name": "Gemini 3.6 Flash (High)", "label": "Gemini 3.6 Flash (High)"},\n'
    '                    {"value": "gemini-3.6-flash-medium", "name": "Gemini 3.6 Flash (Medium)", "label": "Gemini 3.6 Flash (Medium)"},\n'
    '                    {"value": "gemini-3.6-flash-low", "name": "Gemini 3.6 Flash (Low)", "label": "Gemini 3.6 Flash (Low)"},\n'
    '                    {"value": "gemini-3.1-pro-high", "name": "Gemini 3.1 Pro (High)", "label": "Gemini 3.1 Pro (Low)"},\n'
    '                    {"value": "claude-sonnet-4-6", "name": "Claude Sonnet 4.6 (Thinking)", "label": "Claude Sonnet 4.6 (Thinking)"},\n'
    '                    {"value": "claude-opus-4-6-thinking", "name": "Claude Opus 4.6 (Thinking)", "label": "Claude Opus 4.6 (Thinking)"}\n'
    '                ]\n',
    '                "options": _available_model_options()\n',
    "model dropdown reads live catalog",
)

print("all adapter patches applied")
