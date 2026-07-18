#!/usr/bin/env bash
# =============================================================================
# CalcTechnical.sh — Programmer/Technical calculator for Rofi
# Base conversion (hex/dec/bin/oct), bitwise ops. No trig/scientific.
# Uses the comet-glass theme to match the dotfiles design.
# =============================================================================
set -euo pipefail

ROFI_CONFIG="$HOME/.config/rofi/comet-glass.rasi"
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
    rofi -dmenu -i -p "Technical" \
        -mesg "Tech: 0xFF, 0b1010, 255 in hex, 0xFF & 0x0F, 16 << 2" \
        -config "$ROFI_CONFIG"
)"

[[ -z "${expr:-}" ]] && exit 0

# Evaluate with Python (safe AST, bitwise + base conversion only)
raw_output="$(
python3 - "$expr" 2>"$BASES_TMP" <<'PY'
import ast, operator, sys, re

raw = sys.argv[1].strip()
expr = raw.replace("×", "*").replace("÷", "/")

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

BIN_OPS = {
    ast.Add: operator.add, ast.Sub: operator.sub, ast.Mult: operator.mul,
    ast.Div: operator.truediv, ast.FloorDiv: operator.floordiv,
    ast.Mod: operator.mod, ast.Pow: operator.pow,
    ast.BitAnd: operator.and_, ast.BitOr: operator.or_,
    ast.BitXor: operator.xor, ast.LShift: operator.lshift, ast.RShift: operator.rshift,
}
UNARY_OPS = {ast.UAdd: operator.pos, ast.USub: operator.neg, ast.Invert: operator.invert}

def eval_node(node):
    if isinstance(node, ast.Expression): return eval_node(node.body)
    if isinstance(node, ast.Constant):
        if isinstance(node.value, (int, float)): return node.value
        raise ValueError(f"invalid constant: {node.value!r}")
    if isinstance(node, ast.UnaryOp) and type(node.op) in UNARY_OPS:
        return UNARY_OPS[type(node.op)](eval_node(node.operand))
    if isinstance(node, ast.BinOp) and type(node.op) in BIN_OPS:
        return BIN_OPS[type(node.op)](eval_node(node.left), eval_node(node.right))
    raise ValueError("invalid expression — no functions or names allowed")

def to_base(n, base):
    n = int(n)
    if base == "hex": return f"0x{n:X}"
    if base == "dec": return str(n)
    if base == "bin": return f"0b{n:b}"
    if base == "oct": return f"0o{n:o}"
    raise ValueError(f"unknown base: {base}")

try:
    tree = ast.parse(expr, mode="eval")
    value = eval_node(tree)
    is_int_like = isinstance(value, int) or (isinstance(value, float) and value.is_integer())
    int_value = int(value) if is_int_like else None

    if convert_to:
        if int_value is None:
            print("Error: base conversion needs an integer result"); sys.exit(1)
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
    print("Error: division by zero"); sys.exit(1)
except ValueError as e:
    print(f"Error: {e}"); sys.exit(1)
except Exception as e:
    print(f"Error: invalid expression ({type(e).__name__})"); sys.exit(1)
PY
)" || true

result="$(printf '%s' "$raw_output" | head -n1)"
hex_line="$(grep -m1 '^__HEX__' "$BASES_TMP" 2>/dev/null | cut -d' ' -f2- || true)"
bin_line="$(grep -m1 '^__BIN__' "$BASES_TMP" 2>/dev/null | cut -d' ' -f2- || true)"
oct_line="$(grep -m1 '^__OCT__' "$BASES_TMP" 2>/dev/null | cut -d' ' -f2- || true)"

[[ -z "${result:-}" ]] && exit 1

if [[ "$result" == Error:* ]]; then
    notify-send "Calculator" "$result" 2>/dev/null || true
    exit 1
fi

# Result menu — show all bases, select to copy
menu_items="$result"
[[ -n "$hex_line" ]] && menu_items+="$(printf '\nhex: %s' "$hex_line")"
[[ -n "$bin_line" ]] && menu_items+="$(printf '\nbin: %s' "$bin_line")"
[[ -n "$oct_line" ]] && menu_items+="$(printf '\noct: %s' "$oct_line")"

choice="$(printf '%s\n' "$menu_items" | rofi -dmenu -i -p "Result" -config "$ROFI_CONFIG")"
[[ -z "${choice:-}" ]] && exit 0

copy_val="$choice"
case "$choice" in
    hex:\ *) copy_val="${choice#hex: }" ;;
    bin:\ *) copy_val="${choice#bin: }" ;;
    oct:\ *) copy_val="${choice#oct: }" ;;
esac

printf '%s' "$copy_val" | wl-copy
notify-send "Calculator" "Copied: $copy_val" 2>/dev/null || true
