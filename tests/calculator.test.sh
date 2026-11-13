#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
calculator="$repo_root/hypr/.config/hypr/scripts/calculator.sh"
test_root=$(mktemp -d -t calculator-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT
real_path=$PATH

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_eq() {
  [[ "$1" == "$2" ]] || fail "expected [$1], got [$2]"
}

assert_has() {
  grep -Fq -- "$2" "$1" || fail "$1 does not contain [$2]: $(cat "$1")"
}

mkdir -p "$test_root/bin" "$test_root/config/rofi"

# Fake rofi. Each call reads line N of $CALC_RUN/replies, "<exit status> <index>:<typed>",
# the way -format i:f prints it (exit 10 is Ctrl+Enter). No line left means Escape.
# Call N's arguments (one per line) and menu rows land in args.N and menu.N.
cat > "$test_root/bin/rofi" <<'SH'
#!/usr/bin/env bash
count=0
[[ -f "$CALC_RUN/count" ]] && count=$(<"$CALC_RUN/count")
count=$((count + 1))
printf '%s' "$count" > "$CALC_RUN/count"
printf '%s\n' "$@" > "$CALC_RUN/args.$count"
cat > "$CALC_RUN/menu.$count"
reply=$(sed -n "${count}p" "$CALC_RUN/replies" 2>/dev/null)
[[ -n "$reply" ]] || exit 1
printf '%s\n' "${reply#* }"
exit "${reply%% *}"
SH
cat > "$test_root/bin/wl-copy" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$CALC_RUN/clipboard-args"
cat > "$CALC_RUN/clipboard"
SH
cat > "$test_root/bin/notify-send" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CALC_RUN/notifications"
SH
# Minimal qalc stand-in: integer arithmetic, plus the failure shapes real qalc
# shows. Like qalc it prints a Unicode minus unless told 'unicode off', and
# only names an error outside terse mode.
cat > "$test_root/bin/qalc" <<'SH'
#!/usr/bin/env bash
terse=0 unicode=1 expr=""
while (($#)); do
  case $1 in
    -t) terse=1 ;;
    -m) shift ;;
    -defaults) printf 'defaults\n' >> "$CALC_RUN/qalc-settings" ;;
    -s) [[ "$2" == 'unicode off' ]] && unicode=0
      printf '%s\n' "$2" >> "$CALC_RUN/qalc-settings"; shift ;;
    *) expr=$1 ;;
  esac
  shift
done
printf '%s\n' "$expr" >> "$CALC_RUN/qalc-log"
expr=${expr# }
approx=""
case $expr in
  *'sqrt('*)
    ((terse)) || printf 'error: You need at least 1 argument (Value) in function sqrt().\n'
    printf 'sqrt()\n'
    exit 1 ;;
  1/0) out='1 / 0' ;;
  ans+1) out='1 + undefined' ;;
  'tan(pi/2)') out='tan(1.570796327)' ;;
  2+x) out='x + 2' ;;
  'x+1=3') out='x = 2' ;;
  '5 kg + 2 m'|'2 m + 5 kg'|'(2 m + 5 kg)') out='5 kg + 2 m' ;;
  '-2 m + 5 kg') out='5 kg - 2 m' ;;
  2+n) out='n + 2' ;;
  '99999999!') out='aborted' ;;
  1/3) out='0.3333333333' approx=1 ;;
  'integrate(x^x,0,1)') out='0.78343051' approx=1 ;;
  '10/3 to decimal') out='3.333333333' ;;
  2^100) out='1.267650600E30' ;;
  '255 to bin') out='0000 0000 1111 1111' ;;
  '63 to oct'|'63 ➜ oct'|'63->oct') out='077' ;;
  '12 ➤ duo'|'12 −> duo') out='10' ;;
  '2 − 5') out='-3' ;;
  '2 kg * 3') out='6 kg' ;;
  *)
    e=${expr//[[:space:]]/}
    (( result = ${e//^/**} ))
    out=$result
    ((result >= 0 || !unicode)) || out=$'\xe2\x88\x92'${result#-} ;;
esac
# Terse mode prints the answer; full mode adds the problem and "approx." as qalc does.
if ((terse)); then
  printf '%s\n' "$out"
else
  printf '%s = %s%s\n' "$expr" "${approx:+approx. }" "$out"
fi
SH
chmod +x "$test_root/bin/"*

history_file="$test_root/.local/state/calculator/history"
run=0

# run_calc REPLY... — one calculator session; replies drive successive rofi screens.
run_calc() {
  run=$((run + 1))
  CALC_RUN="$test_root/run.$run"
  mkdir -p "$CALC_RUN"
  if (($#)); then printf '%s\n' "$@" > "$CALC_RUN/replies"; else : > "$CALC_RUN/replies"; fi
  calc_status=0
  env -u XDG_STATE_HOME CALC_RUN="$CALC_RUN" PATH="$test_root/bin:$real_path" HOME="$test_root" \
    "$calculator" ${CALC_ARGS:-} > "$CALC_RUN/stdout" 2> "$CALC_RUN/stderr" || calc_status=$?
}

clipboard() { cat "$CALC_RUN/clipboard"; }
# run_calc_eval EXPRESSION — the --eval path, with the fake qalc.
run_calc_eval() {
  run=$((run + 1))
  CALC_RUN="$test_root/run.$run"
  mkdir -p "$CALC_RUN"
  calc_status=0
  env -u XDG_STATE_HOME CALC_RUN="$CALC_RUN" PATH="$test_root/bin:$real_path" HOME="$test_root" \
    "$calculator" --eval "$1" > "$CALC_RUN/stdout" 2> "$CALC_RUN/stderr" || calc_status=$?
}
screens() { cat "$CALC_RUN/count"; }
no_copy() { [[ ! -e "$CALC_RUN/clipboard" ]] || fail "$1 copied [$(clipboard)]"; }

# --- Calculating shows the answer and copy choices, without copying yet.
run_calc '0 -1:2 + 3 * 4'
assert_eq 0 "$calc_status"
assert_eq 2 "$(screens)"
no_copy 'calculating'
assert_eq "$(printf '2 + 3 * 4\t14')" "$(<"$history_file")"
assert_has "$CALC_RUN/args.1" 'i:f'
assert_has "$CALC_RUN/args.1" 'Control+Return'
assert_has "$CALC_RUN/args.2" '<span size="xx-large" weight="bold">14</span>'
assert_eq '󰆏  Copy  14' "$(sed -n 1p "$CALC_RUN/menu.2")"
assert_eq '󰅍  Copy  2 + 3 * 4 = 14' "$(sed -n 2p "$CALC_RUN/menu.2")"
assert_eq '󰋚  2 + 3 * 4 = 14' "$(sed -n 3p "$CALC_RUN/menu.2")"
assert_has "$CALC_RUN/qalc-log" ' 2 + 3 * 4'
assert_eq defaults "$(head -n1 "$CALC_RUN/qalc-settings")"
assert_has "$CALC_RUN/qalc-settings" 'precision 10'
assert_has "$CALC_RUN/qalc-settings" 'show ending zeroes on'

# --- Copy the answer.
run_calc '0 -1:6 * 7' '0 0:'
assert_eq 42 "$(clipboard)"
assert_has "$CALC_RUN/clipboard-args" '--type text/plain'
assert_has "$CALC_RUN/notifications" 'Copied: 42'

# --- Copy the problem and answer together.
run_calc '0 -1:6*7' '0 1:'
assert_eq '6*7 = 42' "$(clipboard)"

# --- A fresh window offers the last answer; Enter on it copies straight away.
run_calc '0 0:'
assert_has "$CALC_RUN/args.1" 'Last answer'
assert_eq '󰆏  Copy  42' "$(sed -n 1p "$CALC_RUN/menu.1")"
assert_eq 42 "$(clipboard)"

# --- A repeat moves to the top of history instead of being stored twice.
assert_eq "$(printf '2 + 3 * 4\t14\n6 * 7\t42\n6*7\t42')" "$(<"$history_file")"
run_calc '0 -1:2 + 3 * 4'
assert_eq "$(printf '6 * 7\t42\n6*7\t42\n2 + 3 * 4\t14')" "$(<"$history_file")"
assert_eq 1 "$(grep -cFx '󰋚  2 + 3 * 4 = 14' "$CALC_RUN/menu.2")"

# --- Leading + * / ^ carry on from the answer; a leading - is a negative number.
run_calc '0 -1:*2' '0 1:'
assert_eq '14*2 = 28' "$(clipboard)"
run_calc '0 -1:-5' '0 -1:^2' '0 1:'
assert_eq '(-5)^2 = 25' "$(clipboard)"
# Only an exact decimal answer carries on; the rest say so and keep the text.
for case in '1/3|0.3333333333' '2^100|1.267650600E30' '10/3 to decimal|3.333333333' \
  '255 to bin|0000 0000 1111 1111' '63 to oct|077' '63 ➜ oct|077' \
  '12 ➤ duo|10' '12 −> duo|10' '2 − 5|-3' '63->oct|077' 'integrate(x^x,0,1)|0.78343051' '2 kg * 3|6 kg' 'x+1=3|x = 2'; do
  run_calc "0 -1:${case%%|*}" '0 -1:*2'
  assert_has "$CALC_RUN/args.3" "Can't carry on from ${case#*|}."
  assert_eq '*2' "$(grep -Fx -A1 -- '-filter' "$CALC_RUN/args.3" | tail -n1)"
  no_copy "carrying on from ${case%%|*}"
done

# --- Answers are plain ASCII (qalc's Unicode minus would break pasting).
run_calc '0 -1:2-5' '0 0:'
assert_eq -3 "$(clipboard)"
assert_has "$CALC_RUN/qalc-log" ' 2-5'

# --- A bad problem stays on screen with qalc's reason and nothing is saved.
history_before=$(<"$history_file")
run_calc '0 -1:sqrt(' '0 -1:sqrt(9'
assert_eq 0 "$calc_status"
no_copy 'an error'
assert_has "$CALC_RUN/args.2" 'You need at least 1 argument (Value) in function'
assert_eq '-filter' "$(grep -Fx -- '-filter' "$CALC_RUN/args.2")"
assert_eq 'sqrt(' "$(grep -Fx -A1 -- '-filter' "$CALC_RUN/args.2" | tail -n1)"
assert_has "$CALC_RUN/args.3" 'You need at least 1 argument'
assert_eq "$history_before" "$(<"$history_file")"
run_calc '0 -1:1/0'
assert_has "$CALC_RUN/args.2" "Can't divide by zero"
run_calc '0 -1:ans+1'
assert_has "$CALC_RUN/args.2" 'The answer is undefined'
# qalc exits 0 on these too; none may be offered as an answer.
for case in "tan(pi/2)|Couldn't work that out" "2+x|Couldn't work that out" \
  "5 kg + 2 m|Couldn't work that out" "2 m + 5 kg|Couldn't work that out" \
  "2+n|Couldn't work that out" "(2 m + 5 kg)|Couldn't work that out" \
  "-2 m + 5 kg|Couldn't work that out" "99999999!|That took too long"; do
  run_calc_eval "${case%%|*}"
  assert_eq 1 "$calc_status"
  assert_has "$CALC_RUN/stderr" "${case#*|}"
done
run_calc_eval 'x+1=3'
assert_eq 'x = 2' "$(cat "$CALC_RUN/stdout")"
assert_eq "$history_before" "$(<"$history_file")"

# --- History rows: Ctrl+Enter copies an answer; Enter brings a row back to copy from.
# Rows are: copy answer, copy problem, then history newest first.
printf '2 + 3 * 4\t14\n6 * 7\t42\n' > "$history_file"
run_calc '10 2:'
assert_eq 42 "$(clipboard)"
assert_eq 1 "$(screens)"
run_calc '10 3:2 +'
assert_eq 14 "$(clipboard)"
run_calc '0 3:' '0 1:'
assert_eq '2 + 3 * 4 = 14' "$(clipboard)"
assert_has "$CALC_RUN/args.2" '<span size="xx-large" weight="bold">14</span>'
# Typed text wins over a highlighted row on Enter, and on Ctrl+Enter with no row.
run_calc '0 2:2 + 2' '0 0:'
assert_eq 4 "$(clipboard)"
run_calc '10 -1:1 + 1' '0 0:'
assert_eq 2 "$(clipboard)"

# --- Escape on any screen copies nothing.
run_calc
no_copy 'escape'
assert_eq 1 "$(screens)"
[[ ! -e "$CALC_RUN/notifications" ]] || fail 'escape notified'

# --- Old history: a Unicode minus is mended, and answers qalc never worked out
# (or lines with no answer) are hidden so they cannot be copied.
printf '%s\n' $'2-5\t\xe2\x88\x923' $'tan(pi/2)\ttan(1.570796327)' 'no tab here' \
  $'2 m + 5 kg\t5 kg + 2 m' $'6 * 7\t42' > "$history_file"
run_calc '10 3:'
assert_eq "$(printf '%s\n' '󰆏  Copy  42' '󰅍  Copy  6 * 7 = 42' '󰋚  6 * 7 = 42' '󰋚  2-5 = -3')" \
  "$(cat "$CALC_RUN/menu.1")"
assert_eq -3 "$(clipboard)"

# Repeating an old Unicode-minus entry replaces it instead of adding a twin.
printf '%s\n' $'2-5\t\xe2\x88\x923' > "$history_file"
run_calc '0 -1:2-5'
assert_eq "$(printf '2-5\t-3')" "$(<"$history_file")"
# Carrying on from a past answer first checks its problem still gives it:
# "0.33" saved under old two-decimal settings is refused, "42" is used.
printf '%s\n' $'1/3\t0.33' > "$history_file"
run_calc '0 -1:*3'
assert_has "$CALC_RUN/args.2" "Can't carry on from 0.33."
no_copy 'carrying on from a stale past answer'
printf '%s\n' $'6 * 7\t42' > "$history_file"
run_calc '0 -1:*2' '0 1:'
assert_eq '42*2 = 84' "$(clipboard)"
# The past answer's problem is run through qalc again, as well as the new problem.
assert_eq "$(printf '%s\n' ' 42*2' ' 6 * 7')" "$(LC_ALL=C sort "$CALC_RUN/qalc-log")"
# A past answer its problem no longer gives is refused.
printf '%s\n' $'6 * 7\t2' > "$history_file"
run_calc '0 -1:*3'
assert_has "$CALC_RUN/args.2" "Can't carry on from 2."
# A history row brought back after a fresh answer is re-checked as well.
printf '%s\n' $'1/3\t0.33' > "$history_file"
run_calc '0 -1:6*7' '0 3:' '0 -1:*3'
assert_has "$CALC_RUN/args.4" "Can't carry on from 0.33."
! grep -Fq '0.33*3' "$history_file" || fail 'carried on from a stale history row'
# An answer that can never carry on is refused without starting qalc again.
printf '%s\n' $'2 kg * 3\t6 kg' > "$history_file"
run_calc '0 -1:*2'
assert_has "$CALC_RUN/args.2" "Can't carry on from 6 kg."
[[ ! -e "$CALC_RUN/qalc-log" ]] || fail 'checked an answer that cannot carry on'

# --- Problems are escaped for rofi's Pango markup.
printf '%s\n' $'1 < 2 & 3 > 2\ttrue' > "$history_file"
run_calc
assert_has "$CALC_RUN/args.1" '1 &lt; 2 &amp; 3 &gt; 2 ='

# --- Empty history: no stray blank row, and Enter on nothing closes.
rm -f "$history_file"
run_calc '0 -1:'
assert_eq '' "$(cat "$CALC_RUN/menu.1")"
assert_has "$CALC_RUN/args.1" 'Type a problem'
no_copy 'empty input'
# A failed "-sqrt(" goes back to rofi as " -sqrt(": a bare "-v" or "-h"
# after -filter would run as rofi's own option.
run_calc '0 -1:-sqrt('
assert_eq ' -sqrt(' "$(grep -Fx -A1 -- '-filter' "$CALC_RUN/args.2" | tail -n1)"
# Output that is not "<index>:<text>" closes rather than being calculated.
run_calc '0 Version: 1.7.5'
assert_eq 1 "$(screens)"
no_copy 'unexpected rofi output'
[[ ! -e "$history_file" ]] || fail 'unexpected rofi output saved history'
# With no answer yet, "*2" is refused rather than read by qalc as 2.
run_calc '0 -1:*2'
assert_has "$CALC_RUN/args.2" "Can't carry on from nothing."
no_copy 'carrying on from nothing'
[[ ! -e "$history_file" ]] || fail 'carrying on from nothing saved history'

# --- History keeps only the newest 100 entries.
mkdir -p "${history_file%/*}"
for n in $(seq 1 120); do printf '%s\t%s\n' "$n" "$n"; done > "$history_file"
run_calc '0 -1:2 + 3 * 4'
assert_eq 100 "$(wc -l < "$history_file")"
assert_eq "$(printf '22\t22')" "$(head -n1 "$history_file")"
assert_eq "$(printf '2 + 3 * 4\t14')" "$(tail -n1 "$history_file")"

# --- An unreadable history file is left alone rather than replaced.
if [[ "$(id -u)" != 0 ]]; then
  chmod 000 "$history_file"
  run_calc '0 -1:2 + 3 * 4' '0 0:'
  chmod 600 "$history_file"
  assert_eq 14 "$(clipboard)"
  assert_eq 100 "$(wc -l < "$history_file")"
fi
[[ -z "$(find "${history_file%/*}" -name 'history.*')" ]] || fail 'history temp file left behind'

# --- A read error still permits calculating; a failed replacement keeps old entries.
printf '#!/usr/bin/env bash\nexit 1\n' > "$test_root/bin/tac"
chmod +x "$test_root/bin/tac"
run_calc '0 -1:2 + 3 * 4' '0 0:'
assert_eq 14 "$(clipboard)"
assert_eq '' "$(cat "$CALC_RUN/menu.1")"
rm "$test_root/bin/tac"
history_before=$(<"$history_file")
printf '#!/usr/bin/env bash\nexit 1\n' > "$test_root/bin/mv"
chmod +x "$test_root/bin/mv"
run_calc '0 -1:7 + 7' '0 0:'
assert_eq 14 "$(clipboard)"
assert_eq "$history_before" "$(<"$history_file")"
[[ -z "$(find "${history_file%/*}" -name 'history.*')" ]] || fail 'failed replacement left temporary history'
rm "$test_root/bin/mv"

# --- Concurrent instances keep every result.
cat > "$test_root/bin/tail" <<'SH'
#!/usr/bin/env bash
sleep 0.1
exec /usr/bin/tail "$@"
SH
chmod +x "$test_root/bin/tail"
rm -f "$history_file"
pids=()
for n in {1..8}; do
  run_calc "0 -1:$n + 10" &
  pids+=("$!")
  run=$((run + 1))
done
for pid in "${pids[@]}"; do wait "$pid"; done
assert_eq 8 "$(wc -l < "$history_file")"
for n in {1..8}; do
  grep -Fxq "$(printf '%s + 10\t%s' "$n" "$((n + 10))")" "$history_file" ||
    fail "concurrent save lost calculation $n"
done
rm "$test_root/bin/tail"

# --- --dry-run prints instead of copying or saving.
history_before=$(<"$history_file")
CALC_ARGS=--dry-run run_calc '0 -1:6 * 7' '0 1:'
assert_eq "$(printf 'save: 6 * 7 = 42\ncopy: 6 * 7 = 42')" "$(cat "$CALC_RUN/stdout")"
no_copy '--dry-run'
assert_eq "$history_before" "$(<"$history_file")"

# --- --eval, help and bad arguments.
run_calc_eval 2-5
assert_eq 0 "$calc_status"
assert_eq -3 "$(cat "$CALC_RUN/stdout")"
run_calc_eval 1/0
assert_eq 1 "$calc_status"
assert_has "$CALC_RUN/stderr" "Can't divide by zero"
CALC_ARGS=--help run_calc
assert_eq 0 "$calc_status"
assert_has "$CALC_RUN/stdout" 'usage:'
CALC_ARGS=--bogus run_calc
assert_eq 2 "$calc_status"
CALC_ARGS=--eval run_calc
assert_eq 2 "$calc_status"

# --- A missing tool is reported, not silently ignored.
# An absent absolute path, so a system wl-copy is never reached.
CALCULATOR_WL_COPY="$test_root/missing/wl-copy" run_calc '0 -1:1 + 1' '0 0:'
assert_eq 1 "$calc_status"
assert_has "$CALC_RUN/notifications" 'wl-copy is not installed'
no_copy 'a missing wl-copy'

printf 'ok: calculator fixtures\n'

# --- The same answers from the real qalc, when it is installed.
if ! PATH=$real_path command -v qalc >/dev/null 2>&1; then
  printf 'skip: qalc not installed\n'
  exit 0
fi
real_eval() {
  PATH=$real_path HOME="$test_root/real-home" timeout 10 "$calculator" --eval "$1" 2>&1
}
assert_eq 14 "$(real_eval '2 + 3 * 4')"
assert_eq -3 "$(real_eval '2-5')"
assert_eq -2 "$(real_eval '-5+3')"
assert_eq 0.3333333333 "$(real_eval '1/3')"
assert_eq -2.718281828 "$(real_eval '-e')"
assert_eq 'x = 2' "$(real_eval 'x+1=3')"
assert_eq 120 "$(real_eval '5!')"
for bad in '1/0' '(1/0)' '2/(1-1)' 'x + 1' '2+x' 'y*2' 'tan(pi/2)' '50% of 80' '5 kg + 2 m' '2 m + 5 kg' '(2 m + 5 kg)' '-2 m + 5 kg' '2+n' 'ans+1' 'sqrt('; do
  output=$(real_eval "$bad") && fail "real qalc accepted [$bad] as [$output]"
done
[[ "$(real_eval 'sqrt(')" == *argument* ]] || fail 'real qalc error reason was lost'
# Carrying on through a real session: rofi is still the fake, qalc is real.
real_qalc=$(PATH=$real_path command -v qalc)
for problem in '1/3' '63 to oct' '63 ➜ oct' '12 ➞ duo' '12 ➤ duo' '12 −> duo' '63 ➙ oct' \
  '12 ➕ duo' '63->oct' 'integrate(x^x,0,1)' '3 to base 3' 'x+1=3' '1000000000 + rand(100000000000)'; do
  CALCULATOR_QALC=$real_qalc run_calc "0 -1:$problem" '0 -1:*2'
  assert_has "$CALC_RUN/args.3" "Can't carry on from"
  no_copy "carrying on from $problem"
done
CALCULATOR_QALC=$real_qalc run_calc '0 -1:6*7' '0 -1:/4' '0 0:'
assert_eq 10.5 "$(clipboard)"
# qalc's full output shows 7.25 as "7 + 1/4" unless told not to.
CALCULATOR_QALC=$real_qalc run_calc '0 -1:7.25' '0 -1:*4' '0 0:'
assert_eq 29 "$(clipboard)"
assert_eq '2 d + 3 h' "$(real_eval '2 days + 3 hours')"
# Settings the user saved in qalc (octal output, two decimals) are ignored.
odd_home="$test_root/odd-home"
HOME=$odd_home PATH=$real_path qalc -t 1 >/dev/null 2>&1 || true
sed -i 's/^number_base=.*/number_base=8/; s/^max_deci=.*/max_deci=2/; s/^use_max_deci=.*/use_max_deci=1/' \
  "$odd_home/.config/qalculate/qalc.cfg"
assert_eq 077 "$(HOME=$odd_home PATH=$real_path qalc -t 63 2>/dev/null)"
assert_eq 63 "$(PATH=$real_path HOME=$odd_home timeout 10 "$calculator" --eval 63)"
assert_eq 0.3333333333 "$(PATH=$real_path HOME=$odd_home timeout 10 "$calculator" --eval 1/3)"
printf 'ok: calculator with real qalc\n'
