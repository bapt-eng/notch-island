#!/bin/bash
# Hook Claude Code & Cursor pour notifier sous l'encoche à chaque réponse d'agent
MSG="$1"
TITLE="${2:-Claude Code}"

if [ -z "$MSG" ]; then
    MSG="Task completed successfully"
fi

# Diffusion IPC vers NotchIsland
osascript -e "tell application \"System Events\" to do shell script \"echo '$TITLE: $MSG'\"" >/dev/null 2>&1
python3 -c "
import socket
import json

payload = {'title': '$TITLE', 'message': '$MSG', 'type': 'agent_notify'}
# Envoi Cocoa Distributed Notification
import subprocess
subprocess.run(['osascript', '-e', 'tell application id \"com.antigravity.notchisland\" to showMessage \"$MSG\" title \"$TITLE\"'], capture_output=True)
" 2>/dev/null || true
