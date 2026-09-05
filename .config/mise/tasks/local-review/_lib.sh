#!/usr/bin/env bash
# local-review helper の共通ライブラリ。各サブコマンドから source する。
# producer（review-changes / review-ensemble）と consumer（reply-pr-review）が別セッションから同じ review directory の
# event を読み書きするため、解釈がぶれると壊れる部分（event の検証と原子的な追加、thread 状態の導出）だけをここに閉じる。
# 制約: ファイルを削除しない（ln / mv -f だけ）、temporary file は review directory の tmp/ にだけ作る
# shellcheck disable=SC2034,SC2016
set -euo pipefail

LR_EXIT_USAGE=2
LR_EXIT_COLLISION=4
LR_EXIT_INVALID=5
LR_EXIT_WRITE_DENIED=8
LR_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LR_JQ_DIR="$LR_SELF_DIR/_jq"

LR_JQ="$(command -v jq 2>/dev/null)" || { printf '{"ok":false,"error":"missing-dependency","message":"jq not found in PATH"}\n'; exit 1; }

lr_json_str() { printf '%s' "$1" | "$LR_JQ" -Rs .; }
lr_sha256_stdin_24() {
    if command -v shasum >/dev/null 2>&1; then shasum -a 256 | awk '{print substr($1,1,24)}'
    elif command -v sha256sum >/dev/null 2>&1; then sha256sum | awk '{print substr($1,1,24)}'
    else lr_fail 1 missing-dependency "shasum or sha256sum not found in PATH"
    fi
}
lr_sha256_24() { printf '%s' "$1" | lr_sha256_stdin_24; }
lr_fail() { printf '{"ok":false,"error":%s,"message":%s}\n' "$(lr_json_str "$2")" "$(lr_json_str "$3")"; exit "$1"; }
lr_usage() { lr_fail "$LR_EXIT_USAGE" usage "$1"; }
lr_need_value() { [[ $# -ge 2 ]] || lr_usage "$1 requires a value"; }
lr_ensure_dir() { [[ -d "$1" ]] && return 0; mkdir -p -- "$1" 2>/dev/null || lr_fail "$LR_EXIT_WRITE_DENIED" sandbox-write-denied "cannot create $1"; chmod -- 0700 "$1" 2>/dev/null || true; }
lr_mktemp() { mktemp "$LR_TMP_DIR/$1.XXXXXX"; }
lr_move_replace() { mv -f -- "$1" "$2" 2>/dev/null || lr_fail 1 io "rename failed: $1 -> $2"; }
# no-replace 作成。link(2) は宛先があれば EEXIST で原子的に失敗する（BSD の mv -n は原子的でない）。
# 成功後の元ファイルは宛先と同じ inode なので truncate せず、固定名へ rename して片付ける
lr_link_new() { if ln -- "$1" "$2" 2>/dev/null; then return 0; fi; [[ -e "$2" ]] || lr_fail 1 io "link failed: $1 -> $2"; return 1; }

# 第 2 引数 readonly なら存在確認だけ（read-only sandbox でも読み取り系が通る）
lr_review_dir_init() {
    [[ -n "${1:-}" ]] || lr_usage "--review-dir is required"
    [[ -d "$1" ]] || lr_usage "review-dir not found: $1"
    LR_REVIEW_DIR="$(cd "$1" && pwd)"
    LR_TMP_DIR="$LR_REVIEW_DIR/tmp"
    LR_EVENTS_DIR="$LR_REVIEW_DIR/events"
    [[ "${2:-}" == "readonly" ]] && return 0
    lr_ensure_dir "$LR_TMP_DIR"
    lr_ensure_dir "$LR_EVENTS_DIR"
    : > "$LR_TMP_DIR/.write-probe" 2>/dev/null || lr_fail "$LR_EXIT_WRITE_DENIED" sandbox-write-denied "review directory is not writable: $LR_REVIEW_DIR"
}

lr_validate_file() {
    local res id type parent expected base
    "$LR_JQ" -s -e 'length == 1' "$1" >/dev/null 2>&1 || { "$LR_JQ" -n -c --arg file "$1" '{ok:false, errors:["must contain exactly one JSON value"], file:$file, event:null}'; return 0; }
    res="$("$LR_JQ" -c --arg file "$1" -f "$LR_JQ_DIR/validate-event.jq" "$1" 2>/dev/null)" || { "$LR_JQ" -n -c --arg file "$1" '{ok:false, errors:["validator failed"], file:$file, event:null}'; return 0; }
    if "$LR_JQ" -e .ok <<<"$res" >/dev/null; then
        id="$("$LR_JQ" -r .event.id <<<"$res")"; base="${1##*/}"
        case "$1" in "$LR_EVENTS_DIR"/*.json) [[ "$base" == "$id.json" ]] || res="$("$LR_JQ" -c --arg msg "filename must be {id}.json" '.ok=false | .errors += [$msg]' <<<"$res")" ;; esac
        type="$("$LR_JQ" -r .event.type <<<"$res")"
        case "$type" in
            reply|resolved)
                parent="$("$LR_JQ" -r .event.reply_to <<<"$res")"; expected="$type-$(lr_sha256_24 "$parent")"
                [[ "$id" == "$expected" ]] || res="$("$LR_JQ" -c --arg msg "id must be $type-{sha256(reply_to)[0:24]}" '.ok=false | .errors += [$msg]' <<<"$res")"
                ;;
            reviewer-reply)
                expected="$type-$("$LR_JQ" -j '.event.reply_to, "\u0000", .event.body' <<<"$res" | lr_sha256_stdin_24)"
                [[ "$id" == "$expected" ]] || res="$("$LR_JQ" -c --arg msg "id must be reviewer-reply-{sha256(reply_to NUL body)[0:24]}" '.ok=false | .errors += [$msg]' <<<"$res")"
                ;;
        esac
    fi
    printf '%s\n' "$res"
}
# 全 event を検証つきで読み {valid, invalid} を返す
lr_events_load() {
    local f lines="" any=0
    for f in "$LR_EVENTS_DIR"/*.json; do
        [[ -e "$f" ]] || continue
        any=1; lines+="$(lr_validate_file "$f")"$'\n'
    done
    (( any )) || { printf '{"valid":[],"invalid":[]}\n'; return 0; }
    printf '%s' "$lines" | "$LR_JQ" -s '{valid: (map(select(.ok == true) | .event) | sort_by(.id)), invalid: map(select(.ok != true) | {file, errors})}'
}
