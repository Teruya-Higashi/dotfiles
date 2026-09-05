# event 1 件を検証する。入力: event object、引数: $file。出力: {ok, errors, file, event}
# ID はすべて field から導ける形に固定し、別セッションが同じ event を同じ名前で書けるようにする
def is_str: type == "string" and length > 0;
def id_ok: type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$");
def run_seq_ok: type == "number" and . == floor and . >= 1 and . <= 999999;
def req($f; pred; $msg): if (.[$f] | pred) then empty else "\($f): \($msg)" end;
def git_sha: type == "string" and test("^[0-9a-f]{40}([0-9a-f]{24})?$");
def abs_path: type == "string" and startswith("/") and (contains("\u0000") | not);
def pad6: tostring | ("000000" + .)[-6:];
def path_errors:
  if . == null then ["path: required"]
  elif type != "string" or length == 0 then ["path: must be a non-empty string"]
  else . as $p | [
    (if $p | startswith("/") then "path: is absolute" else empty end),
    (if ($p | split("/") | any(. == "" or . == "." or . == "..")) then "path: has empty, . or .. segment" else empty end) ] end;
def line_errors:
  if . == null then []
  elif (type == "number" and . == floor and . > 0) then []
  elif (type == "string" and test("^[1-9][0-9]*-[1-9][0-9]*$")) then (split("-") | map(tonumber) | if .[0] < .[1] then [] else ["line: range must be ascending"] end)
  else ["line: must be a positive integer (number) or an ascending range string N-M"] end;

if type != "object" then {ok: false, errors: ["not a JSON object"], file: $file, event: null}
else . as $e | ($e.type // "") as $t
| [
    req("id"; id_ok; "invalid id"),
    req("type"; (. as $x | ["finding", "review-run", "reply", "reviewer-reply", "resolved"] | index($x) != null); "unknown type"),
    req("created_at"; is_str; "required"),
    (if $t == "finding" then
        req("finding_id"; id_ok; "required"), req("run_seq"; run_seq_ok; "must be an integer from 1 to 999999"), req("body"; is_str; "required"),
        (.path | path_errors | .[]), (.line | line_errors | .[]),
        (if (.finding_id | id_ok) and (.run_seq | run_seq_ok) and .id != "finding-\(.finding_id)-\(.run_seq)" then "id: must be finding-{finding_id}-{run_seq}" else empty end)
     elif $t == "review-run" then
        req("run_seq"; run_seq_ok; "must be an integer from 1 to 999999"), req("diff_fingerprint"; is_str; "required"),
        req("review_id"; id_ok; "invalid review id"),
        req("producer"; (. as $x | ["review-patch", "review-patch-crosscheck"] | index($x) != null); "unknown producer"),
        req("repository_common_dir"; abs_path; "must be an absolute path"), req("worktree_root"; abs_path; "must be an absolute path"),
        req("branch"; is_str; "required"), req("target"; is_str; "required"),
        req("diff_mode"; (. as $x | ["commit-range", "staged", "working"] | index($x) != null); "unknown diff mode"),
        req("findings"; (type == "array" and length == (unique | length) and all(.[]; id_ok and startswith("finding-"))); "must be a unique array of finding event ids"),
        req("actions"; (type == "array" and length == (unique | length) and all(.[]; id_ok and (startswith("reviewer-reply-") or startswith("resolved-")))); "must be a unique array of published reviewer-reply/resolved event ids"),
        req("base_sha"; git_sha; "must be a full Git SHA"), req("head_sha"; git_sha; "must be a full Git SHA"),
        req("diff_args"; (type == "array" and
          (if $e.diff_mode == "commit-range" then . == ["--no-ext-diff", "--no-textconv", ($e.base_sha + ".." + $e.head_sha), "--"]
           elif $e.diff_mode == "staged" then . == ["--no-ext-diff", "--no-textconv", "--cached", "--"]
           elif $e.diff_mode == "working" then . == ["--no-ext-diff", "--no-textconv", "HEAD", "--"]
           else false end)); "must exactly match the safe argv for diff_mode and snapshot"),
        (if .body != null and (.body | type) != "string" then "body: must be a string when present" else empty end),
        (if (.run_seq | run_seq_ok) and .id != ("review-run-" + (.run_seq | pad6)) then "id: must be review-run-{run_seq as 6 digits}" else empty end)
     elif $t == "reply" or $t == "reviewer-reply" or $t == "resolved" then
        req("reply_to"; id_ok; "must be an event id"),
        (if .run_seq != null then "run_seq: is only allowed on finding and review-run" else empty end),
        (if $t != "resolved" then req("body"; is_str; "required") else empty end),
        (if (.id | type) == "string" and (.id | test("^\($t)-[0-9a-f]{24}$") | not) then "id: must be \($t)-{sha256(reply_to)[0:24]}" else empty end),
        (if $t == "reply" and (.reply_to | id_ok) and ((.reply_to | startswith("finding-") or startswith("reviewer-reply-")) | not) then "reply_to: reply must answer a finding or reviewer-reply" else empty end),
        (if $t == "reviewer-reply" and (.reply_to | id_ok) and ((.reply_to | startswith("reply-")) | not) then "reply_to: reviewer-reply must answer a reply" else empty end),
        (if $t == "resolved" and (.reply_to | id_ok) and ((.reply_to | startswith("finding-") or startswith("reply-") or startswith("reviewer-reply-")) | not) then "reply_to: resolved must point at a finding, reply or reviewer-reply" else empty end)
     else empty end)
  ] as $errors
| {ok: ($errors | length == 0), errors: $errors, file: $file, event: $e}
end
