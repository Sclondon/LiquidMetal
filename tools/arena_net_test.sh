#!/bin/bash
# The arena's battle room, tested with two copies of the game on a local server.
#   tools/arena_net_test.sh <path to scareathon-v3/server> [out dir]
# Needs node, and `npm ci` done in that server folder. Prints each copy's checks.
GODOT="${GODOT:-C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe}"
SERVER_DIR="${1:?path to scareathon-v3/server}"
OUT="${2:-${TMPDIR:-/tmp}/liquid-metal-net-test}"
PORT=3112
cd "$(dirname "$0")/.."
mkdir -p "$OUT"
node tools/dev_relay.mjs "$SERVER_DIR" $PORT > "$OUT/relay.log" 2>&1 &
RELAY=$!
sleep 2
timeout 70 "$GODOT" --headless --path . -s res://tests/arena_net_test.gd -- --server=http://127.0.0.1:$PORT --role=a --name=ALPHA > "$OUT/a.log" 2>&1 &
A=$!
sleep 2
timeout 70 "$GODOT" --headless --path . -s res://tests/arena_net_test.gd -- --server=http://127.0.0.1:$PORT --role=b --name=BRAVO > "$OUT/b.log" 2>&1 &
B=$!
wait $A $B
kill $RELAY 2> /dev/null
grep -h "PASS\|FAIL\|SCRIPT ERROR" "$OUT/a.log" "$OUT/b.log" | awk '!seen[$0]++'
cat "$OUT/relay.log" | grep -v "Liquid Metal arena on"
