#!/usr/bin/env bash
# Two-way sync between qstack/claudecode/ and ~/.claude/.
#
# Direction is decided per file from a state file that stores the hash and time
# of the last sync:
#   - only ~/.claude changed since last sync  -> copy to repo      (push)
#   - only the repo changed since last sync   -> copy to ~/.claude (pull)
#   - both changed                            -> conflict, skipped unless --prefer
#   - file exists on one side only            -> copied to the other side
#
# Usage:
#   ./sync.sh                                 # dry run: show what would happen
#   ./sync.sh --apply                         # do it
#   ./sync.sh --apply --prefer newer|local|repo   # also resolve conflicts
#   ./sync.sh status                          # last sync time per file

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL="$HOME/.claude"
STATE="$REPO/.sync-state.tsv"   # rel <TAB> hash <TAB> synced_at

# Synced files, relative to both roots.
list_files() {
  local root="$1"
  [ -d "$root" ] || return 0
  (
    cd "$root"
    [ -d agents ] && find agents -maxdepth 1 -type f -name 'q-*.md'
    [ -d skills ] && find skills -type f -path 'skills/q-*/*'
    [ -d q-workflow ] && find q-workflow -type f
  ) | grep -v '/\.DS_Store$' || true
}

hash_of() { [ -f "$1" ] && shasum -a 256 "$1" | cut -d' ' -f1 || echo ""; }

mtime_of() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1"; }

mtime_str() { date -r "$(mtime_of "$1")" '+%Y-%m-%d %H:%M' 2>/dev/null || date -d "@$(mtime_of "$1")" '+%Y-%m-%d %H:%M'; }

state_get() {  # $1=rel $2=field (2=hash, 3=synced_at)
  [ -f "$STATE" ] || return 0
  awk -F'\t' -v r="$1" -v f="$2" '$1 == r { print $f }' "$STATE"
}

state_set() {  # $1=rel $2=hash
  local tmp
  tmp="$(mktemp)"
  [ -f "$STATE" ] && awk -F'\t' -v r="$1" '$1 != r' "$STATE" > "$tmp"
  printf '%s\t%s\t%s\n' "$1" "$2" "$(date '+%Y-%m-%dT%H:%M:%S%z')" >> "$tmp"
  sort "$tmp" > "$STATE"
  rm -f "$tmp"
}

cmd_status() {
  { list_files "$REPO"; list_files "$LOCAL"; } | sort -u | while read -r rel; do
    at="$(state_get "$rel" 3)"
    printf '%-26s  %s\n' "${at:-never}" "$rel"
  done
}

cmd_sync() {
  local apply="$1" prefer="$2" conflicts=0
  local files
  files="$({ list_files "$REPO"; list_files "$LOCAL"; } | sort -u)"

  while read -r rel; do
    [ -n "$rel" ] || continue
    local lp="$LOCAL/$rel" rp="$REPO/$rel"
    local lh rh base action reason
    lh="$(hash_of "$lp")"; rh="$(hash_of "$rp")"; base="$(state_get "$rel" 2)"

    if [ "$lh" = "$rh" ]; then
      # Record the baseline so future changes have a known direction.
      [ "$apply" = 1 ] && [ "$base" != "$rh" ] && state_set "$rel" "$rh"
      continue
    elif [ -z "$rh" ]; then action=push; reason="new in ~/.claude"
    elif [ -z "$lh" ]; then action=pull; reason="new in repo"
    elif [ "$base" = "$rh" ]; then action=push; reason="changed in ~/.claude"
    elif [ "$base" = "$lh" ]; then action=pull; reason="changed in repo"
    else
      if [ -n "$base" ]; then reason="changed on both sides"; else reason="differs, never synced"; fi
      reason="$reason (local $(mtime_str "$lp"), repo $(mtime_str "$rp"))"
      case "$prefer" in
        local) action=push; reason="$reason, --prefer local" ;;
        repo)  action=pull; reason="$reason, --prefer repo" ;;
        newer)
          if [ "$(mtime_of "$lp")" -ge "$(mtime_of "$rp")" ]; then action=push; else action=pull; fi
          reason="$reason, --prefer newer" ;;
        *) action=conflict ;;
      esac
    fi

    case "$action" in
      push) printf '%-18s  %s  (%s)\n' "~/.claude -> repo" "$rel" "$reason" ;;
      pull) printf '%-18s  %s  (%s)\n' "repo -> ~/.claude" "$rel" "$reason" ;;
      conflict) printf '%-18s  %s  (%s)\n' "CONFLICT" "$rel" "$reason"; conflicts=$((conflicts + 1)); continue ;;
    esac

    if [ "$apply" = 1 ]; then
      local src dst
      if [ "$action" = push ]; then src="$lp"; dst="$rp"; else src="$rp"; dst="$lp"; fi
      mkdir -p "$(dirname "$dst")"
      cp -p "$src" "$dst"
      state_set "$rel" "$(hash_of "$dst")"
    fi
  done <<< "$files"

  [ "$apply" = 1 ] || printf '\nDry run. Re-run with --apply to sync.\n'
  if [ "$conflicts" -gt 0 ]; then
    printf '\n%d conflict(s). Compare with `diff ~/.claude/<path> %s/<path>`, then re-run with --prefer newer|local|repo.\n' "$conflicts" "$REPO"
    return 1
  fi
}

usage() { sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

main() {
  local cmd=sync apply=0 prefer=""
  while [ $# -gt 0 ]; do
    case "$1" in
      status) cmd=status ;;
      sync) cmd=sync ;;
      --apply) apply=1 ;;
      --prefer)
        prefer="${2:-}"; shift
        case "$prefer" in newer|local|repo) ;; *) echo "--prefer needs newer, local or repo" >&2; exit 2 ;; esac ;;
      -h|--help) usage; exit 0 ;;
      *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
    esac
    shift
  done
  if [ "$cmd" = status ]; then cmd_status; else cmd_sync "$apply" "$prefer"; fi
}

main "$@"
