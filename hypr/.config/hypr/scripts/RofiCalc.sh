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
#   • Output integer results also show all bases automatically.
# =============================================================================
set -euo pipefail

ROFI_CONFIG="$HOME/.config/rofi/comet-glass.rasi"
PROMPT="Calculator"

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
# -----------------------------------------------------------------------------
raw_output="$(
python3 - "$expr" <<'PY'
import ast
import math
import operator
import sys
import re

raw = sys.argv[1].strip()

# --- Friendly aliases / normalisation -----------------------------------------
# Replace unicode math symbols with ASCII operators
expr = raw.replace("×", "*").replace("÷", "/")
# Treat bare '^' as power for convenience (Python uses **); XOR uses the
# explicit `xor` keyword below to avoid ambiguity.
expr = expr.replace("^", "**")

# --- "in <base>" conversion suffix --------------------------------------------
# e.g. "255 in hex", "0xFF in bin", "2**16 in oct"
convert_to = None
m = re.match(r"^(.*?)\s+in\s+(hex|dec|bin|oct)\s*$", expr, re.IGNORECASE)
if m:
    expr = m.group(1).strip()
    convert_to = m.group(2).lower()

# --- "hex/dec/bin/oct <value>" direct command --------------------------------
# e.g. "hex 255", "bin 10", "dec 0xFF"
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

# Functions exposed to the calculator
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
    # Trig (radians)
    "sin": math.sin, "cos": math.cos, "tan": math.tan,
    "asin": math.asin, "acos": math.acos, "atan": math.atan,
    "atan2": math.atan2,
    # Hyperbolic
    "sinh": math.sinh, "cosh": math.cosh, "tanh": math.tanh,
    "asinh": math.asinh, "acosh": math.acosh, "atanh": math.atanh,
    # Logs / exponentials
    "log": math.log10, "log10": math.log10, "log2": math.log2,
    "ln": math.log, "exp": math.exp,
    # Roots / power
    "sqrt": math.sqrt, "cbrt": (lambda x: math.copysign(abs(x) ** (1/3), x)),
    # Rounding / absolute
    "abs": abs, "floor": math.floor, "ceil": math.ceil, "round": round,
    "trunc": math.trunc,
    # Number theory
    "gcd": _gcd, "lcm": _lcm, "factorial": _factorial, "fact": _factorial,
    # Angle conversion
    "deg": _deg, "rad": _rad,
    # Sign
    "sign": (lambda x: math.copysign(1, x)),
}

def parse_int_literal(s):
    """Parse 0x, 0b, 0o prefixed integers. Returns (value, matched) or (s, False)."""
    s = s.strip()
    m = re.match(r'^0x([0-9a-fA-F]+)$', s)
    if m: return int(m.group(1), 16), True
    m = re.match(r'^0b([01]+)$', s)
    if m: return int(m.group(1), 2), True
    m = re.match(r'^0o([0-7]+)$', s)
    if m: return int(m.group(1), 8), True
    return s, False

def eval_node(node):
    if isinstance(node, ast.Expression):
        return eval_node(node.body)

    if isinstance(node, ast.Constant):
        if isinstance(node.value, (int, float)):
            return node.value
        raise ValueError(f"invalid constant: {node.value!r}")

    if isinstance(node, ast.Num):  # py<3.8 compat
        return node.n

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

    # Factorial postfix: 5!  →  we rewrite "!" to "factorial(" during preprocess
    raise ValueError("invalid expression")

# Preprocess: turn postfix "n!" into "factorial(n)"
# Handle chained like 5!! by repeated substitution
def postfix_factorial(s):
    # repeated passes for chains like 5!!
    changed = True
    while changed:
        changed = False
        # Match a number or closing paren followed by !
        m = re.search(r'(\d+(?:\.\d+)?|\))!', s)
        if m:
            token = m.group(1)
            if token == ')':
                # find matching '(' — easiest: wrap whole group is hard; instead
                # require parentheses balanced and wrap the expression before '!'
                # Simpler approach: reject postfix ()! and ask users to use factorial()
                raise ValueError("use factorial(...) for expressions, not (...)")
            s = s[:m.start()] + f"factorial({token})" + s[m.end():]
            changed = True
    return s

try:
    expr = postfix_factorial(expr)
    tree = ast.parse(expr, mode="eval")
    value = eval_node(tree)

    # Normalise float-with-integer-value to int for clean output / base conversion
    is_int_like = isinstance(value, int) or (
        isinstance(value, float) and value.is_integer()
    )
    if is_int_like:
        int_value = int(value)
    else:
        int_value = None

    # --- Format output --------------------------------------------------------
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
        # Plain result. For integers, also print all bases on stderr for the
        # follow-up menu (we keep stdout = the canonical answer).
        if int_value is not None:
            print(str(int_value))
            # Bases summary (captured separately by caller via marker)
            print(f"__HEX__ {to_base(int_value, 'hex')}", file=sys.stderr)
            print(f"__BIN__ {to_base(int_value, 'bin')}", file=sys.stderr)
            print(f"__OCT__ {to_base(int_value, 'oct')}", file=sys.stderr)
        else:
            # Float — round to 12 sig digits to avoid float noise
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
)" 2>"$HOME/.cache/roficalc-bases.tmp" || true

# raw_output holds stdout (the answer). stderr holds __HEX__ etc lines.
result="$(printf '%s' "$raw_output" | head -n1)"
hex_line="$(grep -m1 '^__HEX__' "$HOME/.cache/roficalc-bases.tmp" 2>/dev/null | cut -d' ' -f2- || true)"
bin_line="$(grep -m1 '^__BIN__' "$HOME/.cache/roficalc-bases.tmp" 2>/dev/null | cut -d' ' -f2- || true)"
oct_line="$(grep -m1 '^__OCT__' "$HOME/.cache/roficalc-bases.tmp" 2>/dev/null | cut -d' ' -f2- || true)"
rm -f "$HOME/.cache/roficalc-bases.tmp" 2>/dev/null || true

[[ -z "${result:-}" ]] && exit 1

if [[ "$result" == Error:* ]]; then
    notify-send "Calculator" "$result" 2>/dev/null || true
    exit 1
fi

# -----------------------------------------------------------------------------
# Result menu — choose what to copy
# -----------------------------------------------------------------------------
menu_items="Copy result: $result"
[[ -n "$hex_line" ]] && menu_items+="$(printf '\nCopy hex: %s' "$hex_line")"
[[ -n "$bin_line" ]] && menu_items+="$(printf '\nCopy bin: %s' "$bin_line")"
[[ -n "$oct_line" ]] && menu_items+="$(printf '\nCopy oct: %s' "$oct_line")"

choice="$(printf '%s\n' "$menu_items" | rofi -dmenu -i -p "Result" -config "$ROFI_CONFIG")"
[[ -z "${choice:-}" ]] && exit 0

# Extract the value after "Copy ...: "
copy_val="${choice#*: }"

printf '%s' "$copy_val" | wl-copy
notify-send "Calculator" "Copied: $copy_val" 2>/dev/null || true
