#!/usr/bin/env bash
# lark_forward.sh — Listen for Lark IM messages and forward to a tmux pane.
#
# Usage:
#   ./lark_forward.sh <tmux-target> [options]     # start / start as daemon
#   ./lark_forward.sh --set-target <tmux-target>  # hot-swap target while running
#   ./lark_forward.sh --stop                      # stop daemon
#   ./lark_forward.sh --status                    # show daemon status
#
# Options:
#   --with-sender       Prepend "sender_id: " before the message text
#   --as user|bot       Lark identity (default: bot)
#   --raw               Forward full raw NDJSON line
#   --no-reply-prompt   Do not append the reply instruction suffix
#   --reply-template T  Custom suffix template; supports {msg_id}, {emoji_type},
#                       {reaction_id}, {as_identity}
#                       Default: the script sends a random OK/SaluteFace/Typing/Get reaction
#                       immediately, then tells the agent to delete it before replying
#   --daemon            Run in a persistent background tmux session (auto-restart)
#   --notify-uid        Lark open_id to notify on daemon start (ou_xxx)
#   -h, --help          Show this help
#
# Special slash commands (received via Lark IM, not forwarded to tmux):
#   /showtmux           Capture current tmux pane content and reply to sender

set -uo pipefail

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
DAEMON_SESSION="lark-forward-daemon"
TARGET_FILE="/tmp/lark_forward.target"

DEFAULT_REPLY_TEMPLATE=$(cat <<'EOF'
# 这是一条飞书消息，你必须回复，回复方式：lark-cli im reactions delete --as {as_identity} --params '{"message_id":"{msg_id}","reaction_id":"{reaction_id}"}';lark-cli im +messages-reply --as {as_identity} --message-id {msg_id} --text '你的回复'
EOF
)

ACK_FAILED_REPLY_TEMPLATE=$(cat <<'EOF'
# 自动确认表情发送失败，请直接正式回复：lark-cli im +messages-reply --as {as_identity} --message-id {msg_id} --text '你的回复'
EOF
)

usage() {
    grep '^#' "$0" | grep -v '^#!/' | sed 's/^# \{0,1\}//'
    exit 0
}
die() { echo "Error: $*" >&2; exit 1; }

pick_ack_emoji() {
    local emojis=("OK" "SaluteFace" "Typing" "Get")
    printf '%s' "${emojis[RANDOM % ${#emojis[@]}]}"
}

create_ack_reaction() {
    local msg_id="$1"
    local emoji_type="$2"
    local params data response

    params=$(printf '{"message_id":"%s"}' "$msg_id")
    data=$(printf '{"reaction_type":{"emoji_type":"%s"}}' "$emoji_type")
    response=$(lark-cli im reactions create --as "$AS_IDENTITY" --params "$params" --data "$data" 2>/dev/null) || return 1

    RESPONSE_JSON="$response" python3 - <<'PYEOF'
import json
import os
import sys

try:
    payload = json.loads(os.environ["RESPONSE_JSON"])
except Exception:
    sys.exit(1)

if payload.get("code") not in (None, 0):
    sys.exit(1)

reaction_id = payload.get("data", {}).get("reaction_id")
if not reaction_id:
    sys.exit(1)

print(reaction_id, end="")
PYEOF
}

render_reply_template() {
    local template="$1"
    local msg_id="$2"
    local emoji_type="$3"
    local reaction_id="$4"

    template="${template//\{msg_id\}/$msg_id}"
    template="${template//\{emoji_type\}/$emoji_type}"
    template="${template//\{reaction_id\}/$reaction_id}"
    template="${template//\{as_identity\}/$AS_IDENTITY}"
    printf '%s' "$template"
}

reply_to_message() {
    local msg_id="$1"
    local reply_text="$2"

    lark-cli im +messages-reply \
        --as "$AS_IDENTITY" \
        --message-id "$msg_id" \
        --text "$reply_text" 2>/dev/null
}

capture_tmux_pane() {
    local target="$1"
    tmux capture-pane -p -t "$target" 2>/dev/null
}

# ── JSON extraction via python3 (env var avoids quoting issues) ─────────────
# Outputs: <message_text><TAB><message_id><TAB><slash_command>
py_extract() {
    local with_sender="$1"
    WITH_SENDER="$with_sender" python3 - <<'PYEOF'
import sys, json, os

line = os.environ.get("LARK_EVENT", "")
try:
    ev = json.loads(line)
except Exception:
    sys.exit(1)

msg    = ev.get("event", {}).get("message", {})
sender = ev.get("event", {}).get("sender", {}).get("sender_id", {}).get("open_id", "unknown")
mtype  = msg.get("message_type", "")
msg_id = msg.get("message_id", "")

if not mtype:
    sys.exit(1)

try:
    content = json.loads(msg.get("content", "{}"))
except Exception:
    content = {}

if mtype == "text":
    text = content.get("text", "")
elif mtype == "post":
    title = content.get("title", "")
    parts = [n.get("text", "") for p in content.get("content", [])
             for n in p if n.get("tag") == "text"]
    text = (title + " " if title else "") + "".join(parts)
elif mtype in ("image", "file", "audio", "video", "sticker"):
    text = f"[{mtype} attachment]"
else:
    text = f"[{mtype}]"

normalized_text = text.strip()
slash_command = ""
if mtype == "text" and normalized_text.startswith("/"):
    slash_command = normalized_text

if os.environ.get("WITH_SENDER") == "true":
    text = f"{sender}: {text}"

# TAB-separated: text \t msg_id \t slash_command
print(f"{text}\t{msg_id}\t{slash_command}", end="")
PYEOF
}

# ── Daemon helpers ──────────────────────────────────────────────────────────
daemon_stop() {
    if tmux has-session -t "$DAEMON_SESSION" 2>/dev/null; then
        tmux kill-session -t "$DAEMON_SESSION" && echo "Daemon stopped."
    else
        echo "No daemon running."
    fi
    rm -f "$TARGET_FILE"
}

daemon_status() {
    if tmux has-session -t "$DAEMON_SESSION" 2>/dev/null; then
        echo "Daemon RUNNING in tmux session: $DAEMON_SESSION"
        echo "Current target: $(cat "$TARGET_FILE" 2>/dev/null || echo '(unknown)')"
        echo "Attach: tmux attach -t $DAEMON_SESSION"
    else
        echo "Daemon NOT running."
    fi
}

daemon_start() {
    local target="$1"; shift
    local extra="$*"
    if tmux has-session -t "$DAEMON_SESSION" 2>/dev/null; then
        echo "Daemon already running. Use --stop first, or --set-target to hot-swap."
        daemon_status; exit 0
    fi
    local wrapper="/tmp/lark_forward_daemon.sh"
    cat > "$wrapper" <<WRAPPER
#!/usr/bin/env bash
while true; do
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Starting..."
    bash "$SCRIPT_PATH" "$target" $extra
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] Exited — restarting in 5s..."
    sleep 5
done
WRAPPER
    chmod +x "$wrapper"
    tmux new-session -d -s "$DAEMON_SESSION" -x 220 -y 30 "bash $wrapper"
    echo "Daemon started → session '$DAEMON_SESSION'"
    echo "View logs : tmux attach -t $DAEMON_SESSION"
    echo "Hot-swap  : $SCRIPT_PATH --set-target <new-target>"
    echo "Stop      : $SCRIPT_PATH --stop"
}

# ── Argument parsing ────────────────────────────────────────────────────────
TMUX_TARGET=""
WITH_SENDER=false
AS_IDENTITY="bot"
RAW_MODE=false
DAEMON_MODE=false
NOTIFY_UID=""
SET_TARGET=""
REPLY_PROMPT=true
REPLY_TEMPLATE="$DEFAULT_REPLY_TEMPLATE"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)           usage ;;
        --stop)              daemon_stop; exit 0 ;;
        --status)            daemon_status; exit 0 ;;
        --set-target)        SET_TARGET="${2:?--set-target requires a value}"; shift 2 ;;
        --with-sender)       WITH_SENDER=true   ; shift ;;
        --as)                AS_IDENTITY="$2"   ; shift 2 ;;
        --raw)               RAW_MODE=true      ; shift ;;
        --daemon)            DAEMON_MODE=true   ; shift ;;
        --notify-uid)        NOTIFY_UID="$2"    ; shift 2 ;;
        --no-reply-prompt)   REPLY_PROMPT=false ; shift ;;
        --reply-template)    REPLY_TEMPLATE="$2"; shift 2 ;;
        -*)                  die "Unknown option: $1" ;;
        *)
            [[ -n "$TMUX_TARGET" ]] && die "Unexpected argument: $1"
            TMUX_TARGET="$1"; shift ;;
    esac
done

# ── Hot-swap target ─────────────────────────────────────────────────────────
if [[ -n "$SET_TARGET" ]]; then
    printf '%s' "$SET_TARGET" > "$TARGET_FILE"
    echo "Target updated → $SET_TARGET  (takes effect on next message)"
    exit 0
fi

[[ -z "$TMUX_TARGET" ]] && die "tmux-target is required. Run with --help for usage."

# ── Daemon mode ─────────────────────────────────────────────────────────────
if $DAEMON_MODE; then
    extra=""
    $WITH_SENDER     && extra+=" --with-sender"
    $RAW_MODE        && extra+=" --raw"
    $REPLY_PROMPT    || extra+=" --no-reply-prompt"
    [[ "$AS_IDENTITY"   != "bot"                   ]] && extra+=" --as $AS_IDENTITY"
    [[ -n "$NOTIFY_UID"                            ]] && extra+=" --notify-uid $NOTIFY_UID"
    [[ "$REPLY_TEMPLATE" != "$DEFAULT_REPLY_TEMPLATE" ]] && extra+=" --reply-template $(printf '%q' "$REPLY_TEMPLATE")"
    daemon_start "$TMUX_TARGET" "$extra"
    exit 0
fi

# ── Dependency check ────────────────────────────────────────────────────────
for cmd in lark-cli python3 tmux; do
    command -v "$cmd" &>/dev/null || die "'$cmd' not found in PATH"
done

if ! tmux list-panes -t "$TMUX_TARGET" &>/dev/null; then
    echo "Warning: tmux pane '$TMUX_TARGET' not found — will still attempt forwarding." >&2
fi

printf '%s' "$TMUX_TARGET" > "$TARGET_FILE"

# ── Startup notification ────────────────────────────────────────────────────
startup_msg="[lark_forward] 已启动消息转发，当前转发到 tmux[$TMUX_TARGET]。"
echo "$startup_msg"
if [[ -n "$NOTIFY_UID" ]]; then
    lark-cli im +messages-send \
        --user-id "$NOTIFY_UID" \
        --text "$startup_msg" \
        --as bot 2>/dev/null \
        && echo "Startup notification sent to $NOTIFY_UID" \
        || echo "Warning: failed to send startup notification" >&2
fi

# ── Main loop ───────────────────────────────────────────────────────────────
echo "Listening... (Ctrl+C to stop)"

lark-cli event +subscribe \
    --event-types im.message.receive_v1 \
    --as "$AS_IDENTITY" \
    --quiet \
2>/dev/null | \
while IFS= read -r line; do
    [[ -z "$line" ]] && continue

    current_target=$(cat "$TARGET_FILE" 2>/dev/null || echo "$TMUX_TARGET")

    if $RAW_MODE; then
        payload="$line"
    else
        with_s=$($WITH_SENDER && echo true || echo false)
        result=$(LARK_EVENT="$line" py_extract "$with_s") || continue
        msg_text="${result%%$'\t'*}"
        rest="${result#*$'\t'}"
        msg_id="${rest%%$'\t'*}"
        slash_command="${rest#*$'\t'}"
        [[ -z "$msg_text" ]] && continue

        if [[ -n "$slash_command" ]]; then
            if [[ "$slash_command" == "/showtmux" ]]; then
                ts=$(date '+%H:%M:%S')
                echo "[$ts] [$current_target] /showtmux requested"
                pane_content="$(capture_tmux_pane "$current_target")"
                if [[ -z "$pane_content" ]]; then
                    reply_text="无法读取 tmux[$current_target] 的内容（pane 可能不存在或为空）"
                else
                    reply_text="tmux[$current_target] 当前内容："$'\n'"$pane_content"
                fi
                if [[ -n "$msg_id" ]]; then
                    reply_to_message "$msg_id" "$reply_text" \
                        || echo "Warning: failed to reply for /showtmux on $msg_id" >&2
                fi
                continue
            fi
            payload="$slash_command"
        elif $REPLY_PROMPT && [[ -n "$msg_id" ]]; then
            ack_emoji="$(pick_ack_emoji)"
            if reaction_id="$(create_ack_reaction "$msg_id" "$ack_emoji")"; then
                suffix="$(render_reply_template "$REPLY_TEMPLATE" "$msg_id" "$ack_emoji" "$reaction_id")"
            else
                echo "Warning: failed to add ack reaction for message $msg_id" >&2
                suffix="$(render_reply_template "$ACK_FAILED_REPLY_TEMPLATE" "$msg_id" "$ack_emoji" "")"
            fi
            payload="$msg_text"$'\n'"$suffix"
        else
            payload="$msg_text"
        fi
    fi

    ts=$(date '+%H:%M:%S')
    echo "[$ts] [$current_target] → $payload"

    if ! printf '%s' "$payload" | tmux load-buffer -b lf_send - 2>/dev/null \
        || ! tmux paste-buffer -p -d -b lf_send -t "$current_target" 2>/dev/null; then
        echo "Warning: failed to send to tmux[$current_target]" >&2
        continue
    fi
    sleep 0.5 && tmux send-keys -t "$current_target" Enter 2>/dev/null
    if [[ -n "${slash_command:-}" && -n "${msg_id:-}" ]]; then
        reply_text="已经将${slash_command}命令转发到 ${current_target}"
        reply_to_message "$msg_id" "$reply_text" \
            || echo "Warning: failed to reply for slash command message $msg_id" >&2
    fi
done
