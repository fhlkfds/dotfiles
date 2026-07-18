#!/usr/bin/env bash
# =============================================================================
# RofiCalc.sh — Scientific & Technical Calculator for Rofi
# =============================================================================
# Features:
#   • Arithmetic: + - * / % // **  with () grouping
#   • Scientific: sin cos tan asin acos atan sinh cosh tanh
#                 log (base 10) ln (natural) exp sqrt abs
#                 floor ceil round gcd lcm factorial(!) deg→rad rad→deg
#   • Constants: pi e tau phi
#   • Bitwise: & | ^ ~ << >>
#   • Base conversion (programmer mode):
#       - Auto-detect prefixes:  0xFF  0b1010  0o17  → evaluated as integers
#       - Convert result:        255 → hex   |  0xFF → dec   |  via "in" keyword
#         e.g.  "255 in hex"   → "0xFF"
#               "0xFF in bin"  → "0b11111111"
#               "2**16 in hex" → "0x10000"
#       - Direct convert cmd:    "hex 255" "bin 10" "dec 0xFF" "oct 17"
#   • Integer results show all bases automatically.
#   • Selecting a result copies it to clipboard.
# =============================================================================
set -euo pipefail

ROFI_CONFIG="$HOME/.config/rofi/comet-glass.rasi"
PROMPT="Calculator"

# Use XDG cache dir with fallback; create a unique temp file with cleanup.
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}"
mkdir -p -- "$CACHE_DIR" 2>/dev/null || true
BASES_TMP="$(mktemp "$CACHE_DIR/roficalc.XXXXXX" 2>/dev/null || mktemp)"
trap 'rm -f -- "$BASES_TMP"' EXIT

if ! command -v rofi >/dev/null 2>&1; then
    notify-send "Calculator" "rofi is not installed" 2>/dev/null || true
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    notify-send "Calculator" "python3 is not installed" 2>/dev/null || true
    exit 1
fi

expr="$(
    rofi -dmenu \
        -i \
        -p "$PROMPT" \
        -mesg "Sci: sin/cos/tan/log/ln/sqrt/exp/abs  •  Constants: pi,e,tau  •  Bases: 0x 0b 0o  •  Convert: '255 in hex' or 'hex 255'" \
        -config "$ROFI_CONFIG"
)"

[[ -z "${expr:-}" ]] && exit 0

# -----------------------------------------------------------------------------
# Evaluate + format with Python (safe AST-based evaluator, no eval())
# The 2> redirect MUST be inside the command substitution, attached to python3,
# so __HEX__/__BIN__/__OCT__ markers on stderr are captured to the temp file.
# -----------------------------------------------------------------------------
raw_output="$(
python3 - "$expr" 2>"$BASES_TMP" <<'PY'
import ast
import math
import operator
import sys
import re

raw = sys.argv[1].strip()

# --- Friendly aliases / normalisation -----------------------------------------
expr = raw.replace("×", "*").replace("÷", "/")
expr = expr.replace("^", "**")

# --- "in <base>" conversion suffix --------------------------------------------
convert_to = None
m = re.match(r"^(.*?)\s+in\s+(hex|dec|bin|oct)\s*$", expr, re.IGNORECASE)
if m:
    expr = m.group(1).strip()
    convert_to = m.group(2).lower()

# --- "hex/dec/bin/oct <value>" direct command --------------------------------
cmd_m = re.match(r"^(hex|dec|bin|oct)\s+(.+)$", expr, re.IGNORECASE)
if cmd_m and convert_to is None:
    convert_to = cmd_m.group(1).lower()
    expr = cmd_m.group(2).strip()

# --- Safe evaluator -----------------------------------------------------------
CONSTANTS = {
    "pi": math.pi,
    "e": math.e,
    "tau": math.tau,
    "phi": (1 + math.sqrt(5)) / 2,
    "inf": math.inf,
}

BIN_OPS = {
    ast.Add: operator.add,
    ast.Sub: operator.sub,
    ast.Mult: operator.mul,
    ast.Div: operator.truediv,
    ast.FloorDiv: operator.floordiv,
    ast.Mod: operator.mod,
    ast.Pow: operator.pow,
    ast.BitAnd: operator.and_,
    ast.BitOr: operator.or_,
    ast.BitXor: operator.xor,
    ast.LShift: operator.lshift,
    ast.RShift: operator.rshift,
}

UNARY_OPS = {
    ast.UAdd: operator.pos,
    ast.USub: operator.neg,
    ast.Invert: operator.invert,
}

def _factorial(n):
    if isinstance(n, float) and n.is_integer():
        n = int(n)
    if not isinstance(n, int):
        raise ValueError("factorial requires an integer")
    if n < 0:
        raise ValueError("factorial of negative number")
    return math.factorial(n)

def _gcd(a, b):
    return math.gcd(int(a), int(b))

def _lcm(a, b):
    a, b = int(a), int(b)
    return abs(a * b) // math.gcd(a, b) if a and b else 0

def _deg(rad):
    return math.degrees(rad)

def _rad(deg):
    return math.radians(deg)

FUNCS = {
    "sin": math.sin, "cos": math.cos, "tan": math.tan,
    "asin": math.asin, "acos": math.acos, "atan": math.atan,
    "atan2": math.atan2,
    "sinh": math.sinh, "cosh": math.cosh, "tanh": math.tanh,
    "asinh": math.asinh, "acosh": math.acosh, "atanh": math.atanh,
    "log": math.log10, "log10": math.log10, "log2": math.log2,
    "ln": math.log, "exp": math.exp,
    "sqrt": math.sqrt, "cbrt": (lambda x: math.copysign(abs(x) ** (1/3), x)),
    "abs": abs, "floor": math.floor, "ceil": math.ceil, "round": round,
    "trunc": math.trunc,
    "gcd": _gcd, "lcm": _lcm, "factorial": _factorial, "fact": _factorial,
    "deg": _deg, "rad": _rad,
    "sign": (lambda x: math.copysign(1, x)),
}

def eval_node(node):
    if isinstance(node, ast.Expression):
        return eval_node(node.body)

    # ast.Constant handles all numeric literals in Python 3.8+.
    # The legacy ast.Num branch was removed as a modernization; it is
    # deprecated in 3.12+ and unnecessary since ast.Constant covers it.
    if isinstance(node, ast.Constant):
        if isinstance(node.value, (int, float)):
            return node.value
        raise ValueError(f"invalid constant: {node.value!r}")

    if isinstance(node, ast.Name):
        if node.id in CONSTANTS:
            return CONSTANTS[node.id]
        raise ValueError(f"unknown name: {node.id}")

    if isinstance(node, ast.UnaryOp) and type(node.op) in UNARY_OPS:
        return UNARY_OPS[type(node.op)](eval_node(node.operand))

    if isinstance(node, ast.BinOp) and type(node.op) in BIN_OPS:
        return BIN_OPS[type(node.op)](
            eval_node(node.left), eval_node(node.right)
        )

    if isinstance(node, ast.Call):
        if not isinstance(node.func, ast.Name):
            raise ValueError("only simple function calls allowed")
        fname = node.func.id
        if fname not in FUNCS:
            raise ValueError(f"unknown function: {fname}")
        args = [eval_node(a) for a in node.args]
        return FUNCS[fname](*args)

    raise ValueError("invalid expression")

# Preprocess: turn postfix "n!" into "factorial(n)"
def postfix_factorial(s):
    changed = True
    while changed:
        changed = False
        m = re.search(r'(\d+(?:\.\d+)?|\))!', s)
        if m:
            token = m.group(1)
            if token == ')':
                raise ValueError("use factorial(...) for expressions, not (...)")
            s = s[:m.start()] + f"factorial({token})" + s[m.end():]
            changed = True
    return s

try:
    expr = postfix_factorial(expr)
    tree = ast.parse(expr, mode="eval")
    value = eval_node(tree)

    is_int_like = isinstance(value, int) or (
        isinstance(value, float) and value.is_integer()
    )
    int_value = int(value) if is_int_like else None

    def to_base(n, base):
        n = int(n)
        if base == "hex": return f"0x{n:X}"
        if base == "dec": return str(n)
        if base == "bin": return f"0b{n:b}"
        if base == "oct": return f"0o{n:o}"
        raise ValueError(f"unknown base: {base}")

    if convert_to:
        if int_value is None:
            print("Error: base conversion needs an integer result")
            sys.exit(1)
        print(to_base(int_value, convert_to))
    else:
        if int_value is not None:
            print(str(int_value))
            print(f"__HEX__ {to_base(int_value, 'hex')}", file=sys.stderr)
            print(f"__BIN__ {to_base(int_value, 'bin')}", file=sys.stderr)
            print(f"__OCT__ {to_base(int_value, 'oct')}", file=sys.stderr)
        else:
            print(repr(value) if isinstance(value, float) else str(value))

except ZeroDivisionError:
    print("Error: division by zero")
    sys.exit(1)
except ValueError as e:
    print(f"Error: {e}")
    sys.exit(1)
except Exception as e:
    print(f"Error: invalid expression ({type(e).__name__})")
    sys.exit(1)
PY
)" || true

# raw_output holds stdout (the answer). BASES_TMP holds __HEX__ etc lines
# (captured via the 2> redirect INSIDE the command substitution above).
result="$(printf '%s' "$raw_output" | head -n1)"
hex_line="$(grep -m1 '^__HEX__' "$BASES_TMP" 2>/dev/null | cut -d' ' -f2- || true)"
bin_line="$(grep -m1 '^__BIN__' "$BASES_TMP" 2>/dev/null | cut -d' ' -f2- || true)"
oct_line="$(grep -m1 '^__OCT__' "$BASES_TMP" 2>/dev/null | cut -d' ' -f2- || true)"

[[ -z "${result:-}" ]] && exit 1

if [[ "$result" == Error:* ]]; then
    notify-send "Calculator" "$result" 2>/dev/null || true
    exit 1
fi

# -----------------------------------------------------------------------------
# Result menu — shows results, selecting one copies it
# -----------------------------------------------------------------------------
menu_items="$result"
[[ -n "$hex_line" ]] && menu_items+="$(printf '\nhex: %s' "$hex_line")"
[[ -n "$bin_line" ]] && menu_items+="$(printf '\nbin: %s' "$bin_line")"
[[ -n "$oct_line" ]] && menu_items+="$(printf '\noct: %s' "$oct_line")"

choice="$(printf '%s\n' "$menu_items" | rofi -dmenu -i -p "Result" -config "$ROFI_CONFIG")"
[[ -z "${choice:-}" ]] && exit 0

# Extract the value: if it has a "hex: "/"bin: "/"oct: " prefix, grab after it;
# otherwise the whole line is the value.
copy_val="$choice"
case "$choice" in
    hex:\ *) copy_val="${choice#hex: }" ;;
    bin:\ *) copy_val="${choice#bin: }" ;;
    oct:\ *) copy_val="${choice#oct: }" ;;
esac

printf '%s' "$copy_val" | wl-copy
notify-send "Calculator" "Copied: $copy_val" 2>/dev/null || true
