#!/bin/zsh
# Headless window self-test. Builds Debug (unsigned) into a throwaway DerivedData folder, launches the app once per
# scenario with `open -n -g -j` (never activates, never shows anything: the app parks its windows off-screen), reads
# the JSON each run writes, prints a PASS/FAIL table, then unregisters and deletes the build.
# Also records the frontmost app before and after each scenario to prove OpenText never took focus.
set -uo pipefail

repo=${0:A:h:h}
dd=/tmp/opentext-dd-rely
app=$dd/Build/Products/Debug/OpenText.app
lsr=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
work=$(mktemp -d /tmp/opentext-selftest.XXXXXX)

cleanup() {
  pkill -f "$app/Contents/MacOS/OpenText" 2>/dev/null || true
  [[ -n ${KEEP_BUILD:-} ]] && return
  "$lsr" -u "$app" 2>/dev/null || true
  rm -rf "$dd" "$work"
}
trap cleanup EXIT

cd "$repo"
xcodegen generate --quiet >/dev/null 2>&1 || /opt/homebrew/bin/xcodegen generate --quiet >/dev/null
if [[ -n ${SKIP_BUILD:-} && -d $app ]]; then :; else
xcodebuild -project OpenText.xcodeproj -scheme OpenText -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath "$dd" CODE_SIGNING_ALLOWED=NO build -quiet >"$work/build.log" 2>&1 || {
  echo "BUILD FAILED"; grep -E "error:" "$work/build.log" | cut -c1-300 | sort -u | head -20; exit 2; }
fi

front() {
  osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null \
    || lsappinfo info -only name "$(lsappinfo front)" 2>/dev/null | sed -E 's/.*="(.*)"/\1/' || echo "?"
}

typeset -a rows
failed=0

# run <scenario> <settings-json-or-"keep"> [with-file|with-dir]
run() {
  local name=$1 settingsmode=$2 mode=${3:-}
  [[ -n ${ONLY:-} && ",$ONLY," != *",$name,"* ]] && return
  local d=$work/$name; mkdir -p "$d"
  local settings=$d/settings.json; [[ -n ${4:-} ]] && settings=$work/settings-$4.json
  [[ $settingsmode == keep ]] || print -r -- "${settingsmode//@DIR@/$d/files}" >"$settings"
  local out=$d/result.json; rm -f "$out" "$out.ready"
  local extra=() fileargs=()
  if [[ $mode == with-file ]]; then
    print "hello" >"$d/opened.txt"; fileargs=("$d/opened.txt"); extra=(--selftest-file "$d/opened.txt")
  elif [[ $mode == warm ]]; then
    print "hello" >"$d/opened.txt"; extra=(--selftest-file "$d/opened.txt")
  elif [[ $mode == with-dir ]]; then
    mkdir -p "$d/files"; extra=(--selftest-dir "$d/files")
  fi
  local before after res=PASS note=""
  before=$(front)
  open -n -g -j --env OPENTEXT_SETTINGS_PATH="$settings" -a "$app" "${fileargs[@]}" --args \
    -ApplePersistenceIgnoreState YES --selftest-out "$out" --selftest-script "$name" "${extra[@]}"
  if [[ $mode == warm ]]; then       # second open sent to the already-running instance
    for _ in {1..100}; do [[ -f $out.ready ]] && break; sleep 0.1; done
    open -g -j -a "$app" "$d/opened.txt"
  fi
  local waited=0
  while (( waited < 300 )); do
    sleep 0.1; waited=$((waited + 1))
    pgrep -f "selftest-out $out" >/dev/null || break
  done
  if pgrep -f "selftest-out $out" >/dev/null; then
    pkill -f "selftest-out $out"; res=FAIL; note="timeout 30s"
  fi
  after=$(front)
  if [[ ! -f $out ]]; then res=FAIL; note="$note no result file"
  elif ! python3 -I -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1]))["pass"] else 1)' "$out"; then
    res=FAIL; note="$note $(python3 -I -c 'import json,sys; print("; ".join(json.load(open(sys.argv[1]))["failures"]))' "$out")"
  fi
  [[ $before == "$after" && $after != OpenText ]] || { res=FAIL; note="$note frontmost changed ($before -> $after)"; }
  [[ $res == PASS ]] || failed=1
  rows+=("$res|$name|$before|$after|${note# }")
  [[ $res == PASS ]] || { echo "---- $name result:"; cat "$out" 2>/dev/null; }
}

plain='{"setupShown": true}'
run launch-plain        "$plain"
run launch-with-file    "$plain" with-file
run warm-open          "$plain" warm
run create-opens        "$plain" with-dir
run reopen              "$plain"
run open-rtf            "$plain" with-dir
run open-html           "$plain" with-dir
run open-rtfd           "$plain" with-dir
run first-run-setup     '{}' "" firstrun
run second-run-no-setup keep "" firstrun
dirset='{"setupShown": true, "defaultFolder": "@DIR@", "lastNewFileFormat": "txt"}'
for s in home-open-panel home-controls home-finish-setup setup-buttons home-create-closes doc-save doc-rename doc-resize \
         lock-cancel convert-cancel convert-run quick-create doc-toolbar; do
  run $s "$dirset" with-dir
done

echo
printf '%-5s %-22s %-18s %-18s %s\n' RESULT SCENARIO FRONT-BEFORE FRONT-AFTER NOTES
for r in "${rows[@]}"; do
  IFS='|' read -r st nm b a n <<<"$r"
  printf '%-5s %-22s %-18s %-18s %s\n' "$st" "$nm" "$b" "$a" "$n"
done
exit $failed
