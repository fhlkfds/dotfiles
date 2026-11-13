#!/usr/bin/env bash
# Rofi calculator backed by qalc. Type a problem and press Enter: the
# calculator reopens with the answer at the top, then copy just the answer, the
# whole "problem = answer" line, or press Escape having only looked. Answers
# are plain ASCII ("-3", not qalc's Unicode "−3") so they paste cleanly into
# code and terminals, and anything qalc cannot really work out is reported in
# the window instead of being copied as if it were an answer.
set -euo pipefail
shopt -s extglob

rofi_command=${CALCULATOR_ROFI:-rofi}
qalc_command=${CALCULATOR_QALC:-qalc}
copy_command=${CALCULATOR_WL_COPY:-wl-copy}
notify_command=${CALCULATOR_NOTIFY:-notify-send}
history_file=${CALCULATOR_HISTORY_FILE:-${XDG_STATE_HOME:-$HOME/.local/state}/calculator/history}
history_limit=100
rofi_theme=${CALCULATOR_ROFI_THEME:-$HOME/.config/rofi/calculator.rasi}
if [[ ! -r "$HOME/.config/rofi/current-theme.rasi" || ! -r "$rofi_theme" ]]; then
  rofi_theme=$HOME/.config/rofi/comet-glass.rasi
fi
# Default settings, not whatever the user last saved in qalc (a base, max
# decimals or precision would break the carry-on rule below); neither -defaults
# nor -s is written back to qalc's config.
qalc_settings=(-defaults -s 'unicode off' -s 'precision 10' -s 'show ending zeroes on')
dry_run=0
eval_expression=""
eval_mode=0

usage() {
  cat <<EOF
usage: ${0##*/} [--dry-run] [--eval EXPRESSION]

Opens the calculator. Enter calculates what you typed; on an empty line it
runs the highlighted row: copy the answer, copy "problem = answer", or bring
back a history entry. Ctrl+Enter copies a history row's answer straight away.
Start a line with + * / or ^ to keep going from the answer shown. Escape closes.

  --dry-run          print what would be copied or saved instead of doing it
  --eval EXPRESSION  print the answer to EXPRESSION and exit (1 if it fails)
EOF
}

while (($#)); do
  case $1 in
    --dry-run) dry_run=1 ;;
    --eval)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      eval_mode=1
      eval_expression=$2
      shift
      ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
  shift
done

notify() {
  if command -v "$notify_command" >/dev/null 2>&1; then
    "$notify_command" -a Calculator -u "$1" Calculator "$2" 2>/dev/null || true
  else
    printf 'calculator: %s\n' "$2" >&2
  fi
}

require() {
  local command_name
  for command_name in "$@"; do
    command -v "$command_name" >/dev/null 2>&1 || {
      notify critical "${command_name##*/} is not installed"
      exit 1
    }
  done
}

# same_sum A B — true when A and B add the same signed parts in any order,
# ignoring spaces and brackets: "(-2 m + 5 kg)" and "5 kg - 2 m" do. Pure
# bash, since old history can hold many such rows and each fork costs ~1 ms.
same_sum() {
  local a=${1//[[:space:]()]/} b=${2//[[:space:]()]/} term i
  local -a left right
  IFS=+ read -ra left <<<"${a//-/+-}"
  IFS=+ read -ra right <<<"${b//-/+-}"
  for term in "${left[@]}"; do
    [[ -n "$term" ]] || continue
    for i in "${!right[@]}"; do
      if [[ "${right[i]}" == "$term" ]]; then
        unset 'right[i]'
        continue 2
      fi
    done
    return 1
  done
  for term in "${right[@]}"; do
    [[ -z "$term" ]] || return 1
  done
}

# check_answer ANSWER PROBLEM — sets `fault` to why qalc's answer was not
# really worked out, or to "". qalc exits 0 and hands back what it could not
# do, so an answer that still divides by zero, calls a function
# ("tan(1.570796327)", "rem(50, 1 B)" for "50% of 80") or holds an unknown n,
# x, y or z was not calculated; a solved equation such as "x = 2" is. It also
# echoes back, perhaps reordered, a sum it cannot combine ("2 m + 5 kg" gives
# "5 kg + 2 m"), and prints "aborted" at the time limit.
check_answer() {
  local answer=$1 problem=$2
  fault=""
  if [[ -z "$answer" ]]; then
    fault="No answer"
    return
  fi
  # A plain number cannot fail a check, every regex rule needs "(", "/", n, x,
  # y or z, and an echo worth refusing is a sum, which qalc spaces as " + " or
  # " - ". History loading relies on this to skip most rows.
  [[ "$answer" == *[!0-9.E-]* ]] || return 0
  if [[ "$answer" == aborted ]]; then
    fault="That took too long"
  elif [[ "$answer" == *[\(/nxyz]* ]]; then
    local undefined='(^|[^[:alnum:]_])undefined([^[:alnum:]_]|$)'
    local divide_by_zero='/ ?0([^.0-9]|$)'
    local function_call='[[:alpha:]_][[:alnum:]_]*\('
    local unknown='(^|[^[:alpha:]_])[nxyz]([^[:alnum:]_]|$)'
    if [[ "$answer" =~ $undefined ]]; then
      fault="The answer is undefined"
    elif [[ "$answer" =~ $divide_by_zero ]]; then
      fault="Can't divide by zero"
    elif [[ "$answer" =~ $function_call || ("$answer" =~ $unknown && "$answer" != *=*) ]]; then
      fault="Couldn't work that out"
    fi
  fi
  if [[ -z "$fault" && ("$answer" == *" + "* || "$answer" == *" - "*) ]] &&
    same_sum "$answer" "$problem"; then
    fault="Couldn't work that out"
  fi
}

# Sets `answer` on success; sets `calc_error` and fails otherwise. The leading
# space stops qalc reading a problem such as "-e" as one of its own options.
calculate() {
  local expression=$1 output status=0
  answer=""
  calc_error=""
  output=$("$qalc_command" -t -m 2000 "${qalc_settings[@]}" " $expression" </dev/null 2>/dev/null) ||
    status=$?
  answer=$(sed -n '/[^[:space:]]/{s/^[[:space:]]*//;s/[[:space:]]*$//;p;q;}' <<<"$output")
  if ((status != 0)); then
    # Terse mode hides qalc's reason, so ask again without it, on this rare path only.
    calc_error=$({ "$qalc_command" -m 2000 "${qalc_settings[@]}" " $expression" </dev/null 2>&1 || true; } |
      sed -n '/^error: /{s///;p;q;}')
    calc_error=${calc_error:-"Couldn't calculate that"}
  else
    check_answer "$answer" "$expression"
    calc_error=$fault
  fi
  [[ -z "$calc_error" ]]
}

if ((eval_mode)); then
  require "$qalc_command"
  if calculate "$eval_expression"; then
    printf '%s\n' "$answer"
    exit 0
  fi
  printf 'calculator: %s\n' "$calc_error" >&2
  exit 1
fi

require "$rofi_command" "$qalc_command"
((dry_run)) || require "$copy_command"

copy_text() {
  if ((dry_run)); then
    printf 'copy: %s\n' "$1"
    return
  fi
  printf '%s' "$1" | "$copy_command" --type text/plain
  notify normal "Copied: $1"
}

# History is "problem<TAB>answer" per line, oldest first, newest 100 kept. A
# repeat moves to the top instead of filling the list with copies.
save_history() (
  local dir tmp line
  line=$1
  dir=$(dirname -- "$history_file")
  mkdir -p -- "$dir" || return 1
  exec 9>"$dir/.history.lock" || return 1
  flock -x 9 || return 1
  tmp=$(mktemp "$history_file.XXXXXX") || return 1
  # A failed read (e.g. unreadable history) aborts before the old file is replaced.
  if ! { { [[ ! -e "$history_file" ]] ||
    # Mending an old Unicode minus first lets a repeat of it match.
    sed 's/−/-/g' -- "$history_file" | { grep -vxF -e "$line" || (($? == 1)); } |
    tail -n "$((history_limit - 1))"; } > "$tmp" &&
    printf '%s\n' "$line" >> "$tmp" &&
    mv -f -- "$tmp" "$history_file"; }; then
    rm -f -- "$tmp"
    return 1
  fi
)

# Older versions saved qalc's Unicode minus and answers it never worked out
# ("tan(1.570796327)"); those are mended or hidden so they cannot be copied.
history_entries=()
if [[ -r "$history_file" ]]; then
  history_text=$(tac -- "$history_file" 2>/dev/null) || history_text=""
  history_text=${history_text//−/-}
  saved_entries=()
  [[ -z "$history_text" ]] || mapfile -t saved_entries <<<"$history_text"
  for entry in "${saved_entries[@]}"; do
    [[ "$entry" == *$'\t'* ]] || continue
    answer=${entry#*$'\t'}
    # Only an answer holding something check_answer looks for can fail it; one
    # glob keeps 100 rows at about 1 ms instead of 5 ms of per-row checks.
    if [[ -z "$answer" || "$answer" == *@([\(/nxyz]|" + "|" - "|aborted)* ]]; then
      check_answer "$answer" "${entry%%$'\t'*}"
      [[ -z "$fault" ]] || continue
    fi
    history_entries+=("$entry")
  done
fi

remember() {
  local line="${1//$'\t'/ }"$'\t'"$2" entry kept=()
  if ((dry_run)); then
    printf 'save: %s = %s\n' "$1" "$2"
  else
    save_history "$line" || true
  fi
  for entry in "${history_entries[@]}"; do
    [[ "$entry" == "$line" ]] || kept+=("$entry")
  done
  history_entries=("$line" "${kept[@]:0:history_limit-1}")
}

# "+5", "*2", "/4" or "^2" carry on from the answer on screen. A leading "-"
# stays a negative number, since "-5" is more often meant than "answer - 5".
# Only an exact decimal answer carries on. One qalc may have rounded (ten or
# more digits, or an exponent), one shown in another base ("077" from
# "63 to oct") or anything that is not a number would give a wrong answer.
# qalc converts on " to ", "->" and dozens of Unicode arrows (even "➕"), so
# the problem must also be plain ASCII rather than checked against a list.
# With no answer on screen there is nothing to carry on from; qalc would
# quietly read "*2" as 2. Last, qalc itself must confirm the answer is exact
# and current (confirms_exact): a numeric integral shows "0.78343051", and a
# past answer may come from older settings ("0.33" for 1/3).
carries_on() {
  local typed=${1#"${1%%[![:space:]]*}"}
  [[ "$typed" == [+*/^]* ]]
}

# exact_decimal ANSWER PROBLEM — true when ANSWER is one to carry on from.
exact_decimal() {
  local digits=${1//[-.]/} LC_ALL=C
  while [[ "$digits" == 0* ]]; do digits=${digits#0}; done
  [[ "$1" =~ ^-?[0-9]+(\.[0-9]+)?$ && ${#digits} -lt 10 &&
    "$2" != *[![:print:]]* && ! "$2" =~ [[:space:]]to[[:space:]]|-\> ]]
}

# confirms_exact PROBLEM ANSWER — qalc's full output for PROBLEM ends in
# "= ANSWER", with no "approx." and no warning. "fractions 0" keeps it from
# showing 2.5 as "2 + 1/2".
confirms_exact() {
  local output
  output=$("$qalc_command" -m 2000 "${qalc_settings[@]}" -s 'fractions 0' " $1" </dev/null 2>&1) ||
    return 1
  [[ "$output" != *"approx."* && "$output" != *"warning:"* && "$output" == *" = $2" ]]
}

continue_from_answer() {
  local typed=$1 base=$current_answer
  typed=${typed#"${typed%%[![:space:]]*}"}
  if carries_on "$typed"; then
    [[ "$base" != -* ]] || base="($base)"
    typed=$base$typed
  fi
  printf '%s' "$typed"
}

# markup_escape NAME TEXT — sets NAME without a subshell, which costs a fork.
markup_escape() {
  local text=$2
  text=${text//&/"&amp;"}
  text=${text//</"&lt;"}
  text=${text//>/"&gt;"}
  printf -v "$1" '%s' "$text"
}

current_problem=""
current_answer=""
current_label="Last answer"
if ((${#history_entries[@]})); then
  current_problem=${history_entries[0]%%$'\t'*}
  current_answer=${history_entries[0]#*$'\t'}
fi
error=""
prefill=""
hint="Enter: calculate or pick • + * / ^ carries on • Esc: close"

while :; do
  rows=()
  if [[ -n "$current_answer" ]]; then
    rows+=("󰆏  Copy  $current_answer" "󰅍  Copy  $current_problem = $current_answer")
  fi
  action_count=${#rows[@]}
  for entry in "${history_entries[@]}"; do
    rows+=("󰋚  ${entry/$'\t'/ = }")
  done

  # A calculator display: the problem small, the answer large, then the keys.
  # The error is pre-wrapped: rofi overlaps a self-wrapped message onto the
  # input box when every row is filtered out.
  if [[ -n "$error" ]]; then
    markup_escape shown_error "$(fold -s -w 50 <<<"$error" | sed 's/[[:space:]]*$//')"
    message="<span alpha=\"60%\">Can't calculate that</span>"$'\n'"<b>$shown_error</b>"
  elif [[ -n "$current_answer" ]]; then
    markup_escape shown_problem "$current_problem"
    markup_escape shown_answer "$current_answer"
    message="<span alpha=\"60%\">$current_label · $shown_problem =</span>"$'\n'"<span size=\"xx-large\" weight=\"bold\">$shown_answer</span>"
  else
    message="<span alpha=\"60%\">Type a problem, like 2 + 3 * 4</span>"
  fi
  message+=$'\n'"<span size=\"small\" alpha=\"60%\">$hint</span>"

  rofi_args=(-dmenu -i -format 'i:f' -p "Calculator" -selected-row 0
    -kb-accept-custom '' -kb-custom-1 'Control+Return'
    -mesg "$message" -theme "$rofi_theme")
  # rofi would run a prefill such as "-v" or "-h" as one of its own options.
  [[ "$prefill" != -* ]] || prefill=" $prefill"
  [[ -z "$prefill" ]] || rofi_args+=(-filter "$prefill")

  status=0
  selection=$({ ((${#rows[@]} == 0)) || printf '%s\n' "${rows[@]}"; } |
    "$rofi_command" "${rofi_args[@]}") || status=$?
  [[ "$status" == 0 || "$status" == 10 ]] || exit 0
  [[ "$selection" =~ ^(-1|[0-9]+): ]] || exit 0
  index=${selection%%:*}
  typed=${selection#*:}
  error=""
  prefill=""

  # Enter always calculates typed text; Ctrl+Enter (custom key 1, exit 10)
  # prefers the highlighted row even while text is typed.
  if [[ -n "${typed//[[:space:]]/}" ]] && ! ((status == 10 && index >= 0)); then
    check_pid=""
    if carries_on "$typed" && exact_decimal "$current_answer" "$current_problem"; then
      # Runs alongside the calculation below, so carrying on adds no wait.
      confirms_exact "$current_problem" "$current_answer" &
      check_pid=$!
    fi
    calculated=0
    if ! carries_on "$typed" || [[ -n "$check_pid" ]]; then
      problem=$(continue_from_answer "$typed")
      calculate "$problem" && calculated=1
    fi
    if carries_on "$typed" && ! { [[ -n "$check_pid" ]] && wait "$check_pid"; }; then
      error="Can't carry on from ${current_answer:-nothing}. Type the whole problem."
      prefill=$typed
    elif ((calculated)); then
      current_problem=$problem
      current_answer=$answer
      current_label="Answer"
      remember "$problem" "$answer"
    else
      error=$calc_error
      prefill=$typed
    fi
    continue
  fi

  ((index >= 0)) || exit 0
  if ((index < action_count)); then
    if ((index == 0)); then
      copy_text "$current_answer"
    else
      copy_text "$current_problem = $current_answer"
    fi
    exit 0
  fi

  entry=${history_entries[index - action_count]-}
  [[ -n "$entry" ]] || { notify critical "History entry not found"; exit 1; }
  if ((status == 10)); then
    copy_text "${entry#*$'\t'}"
    exit 0
  fi
  current_problem=${entry%%$'\t'*}
  current_answer=${entry#*$'\t'}
  current_label="Answer"
done
