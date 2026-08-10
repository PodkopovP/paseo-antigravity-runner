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

print("all adapter patches applied")
