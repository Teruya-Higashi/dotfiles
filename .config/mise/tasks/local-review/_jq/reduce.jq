# event を thread 単位に畳む。入力: {valid: [event], invalid: [...]}
# 最新の review-run が参照する finding event だけを対象にし、thread は reply_to を辿る因果順で組む。
# 返信 ID は親ごとに一意（reply-{親} / reviewer-reply-{親}）なので、末尾から次を引くだけで連鎖が決まる
.invalid as $inv | .valid as $all
| if ($inv | length) > 0 then {ok: false, run_seq: null, next_run_seq: null, diff_fingerprint: null, head_sha: null, review_run: null, threads: [], inconsistencies: [{reason:"invalid event files present"}], invalid: $inv}
else ([$all[] | select(.type == "review-run")] | sort_by(.run_seq)) as $runs
| ($runs | max_by(.run_seq)) as $run
| ([$runs[].actions[]]) as $published_actions
| ($all | INDEX(.id)) as $all_by_id
| ([$published_actions[] | select(($all_by_id[.] // null) == null) | {event_id: ., reason:"published action missing"}]) as $action_issues
| ([$all[] | select((.type != "reviewer-reply" and .type != "resolved") or ((.id as $id | $published_actions | index($id)) != null))]) as $ev
| ($ev | INDEX(.id)) as $by_id
| ([$runs[].findings[]] | unique) as $published_findings
| ([$published_actions[] | $by_id[.] as $action | select($action != null and ($by_id[$action.reply_to] // null) == null) | {event_id:$action.id, reply_to:$action.reply_to, reason:"published action parent missing"}]) as $parent_issues
| ([$ev[] as $parent | [$ev[] | select((.type == "reply" or .type == "reviewer-reply") and .reply_to == $parent.id)] | select(length > 1) | {event_id:$parent.id, reason:"multiple message children"}]) as $branch_issues
| def reaches_published_finding($id; $seen):
    if ($seen | index($id)) != null then false
    else ($by_id[$id] // null) as $e
      | if $e == null then false
        elif $e.type == "finding" then ($published_findings | index($id)) != null
        elif ($e.type == "reply" or $e.type == "reviewer-reply" or $e.type == "resolved") then reaches_published_finding($e.reply_to; $seen + [$id])
        else false end
    end;
  ([$ev[] | select(.type == "reply" or .type == "reviewer-reply" or .type == "resolved")
    | select(reaches_published_finding(.id; []) | not)
    | {event_id:.id, reply_to:.reply_to, reason:"event ancestry does not reach a published finding"}]) as $ancestry_issues
| def next($t): [$ev[] | select((.type == "reply" or .type == "reviewer-reply") and .reply_to == $t)] | if length == 1 then .[0] else null end;
  def chain($start): [$start] | until(next(.[-1].id) == null; . + [next(.[-1].id)]);
  def is_resolved($tail): [$ev[] | select(.type == "resolved" and .reply_to == $tail)] | length > 0;
  if $run == null then {ok: true, run_seq: null, next_run_seq: 1, diff_fingerprint: null, head_sha: null, review_run: null, threads: [], inconsistencies: ($action_issues + $parent_issues + $branch_issues + $ancestry_issues), invalid: $inv}
  else
    [ $run.findings[] | . as $fid_event
      | ($by_id[$fid_event] // null) as $f
      | if $f == null or $f.type != "finding" then {inconsistency: {event_id: $fid_event, reason: "finding event missing"}}
        else chain($f) as $c | ($c[-1].id) as $tail
          | {thread: {finding_id: $f.finding_id, finding_event_id: $f.id, path: $f.path, line: ($f.line // null),
                      state: (if is_resolved($tail) then "resolved" elif $c[-1].type == "reply" then "replied-unresolved" else "unreplied" end),
                      tail_event_id: $tail,
                      messages: ($c | map({event_id: .id, type, body, created_at}))}}
        end ] as $rows
    | ([$rows[] | select(.thread) | .thread] | group_by(.finding_id)
       | map(select(length > 1) | {finding_id:.[0].finding_id, event_ids:map(.finding_event_id), reason:"multiple finding events for one finding_id in latest run"})) as $duplicate_finding_issues
    # 前 run の finding が継続も resolve もされずに消えていれば producer の漏れ（continue か resolve のどちらかが要る）
    | ([$ev[] | select(.type == "review-run" and .run_seq < $run.run_seq)] | max_by(.run_seq)) as $prev
    | (if $prev == null then [] else
        [ $prev.findings[] | select(. as $x | ($run.findings | index($x)) == null) | . as $old
          | ($by_id[$old] // null) as $f
          | select($f != null and $f.type == "finding") | (chain($f)[-1].id) as $tail | select(is_resolved($tail) | not)
          | {event_id: $old, finding_id: $f.finding_id, tail_event_id: $tail, reason: "finding dropped from run \($run.run_seq) without a resolved event"} ] end) as $dropped
    | {ok: true, run_seq: $run.run_seq, next_run_seq: (([$all[] | select(.type == "finding" or .type == "review-run") | .run_seq] | max // 0) + 1), diff_fingerprint: $run.diff_fingerprint, head_sha: $run.head_sha, review_run: $run,
       threads: ($rows | map(select(.thread) | .thread)),
       inconsistencies: ($action_issues + $parent_issues + $branch_issues + $ancestry_issues + $duplicate_finding_issues + ($rows | map(select(.inconsistency) | .inconsistency)) + $dropped),
       invalid: $inv}
  end
end
