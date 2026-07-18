#!/usr/bin/env bash
# =============================================================================
# CalcClassic.sh — Basic arithmetic calculator for Rofi
# Clean and simple: + - * / % and parentheses. Nothing else.
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
    rofi -dmenu -i -p "Classic" \
        -mesg "Basic: 1+1, (8*3)-2, 100/7" \
        -config "$ROFI_CONFIG"
)"

[[ -z "${expr:-}" ]] && exit 0

# Evaluate with Python (safe AST, basic arithmetic only)
raw_output="$(
python3 - "$expr" 2>"$BASES_TMP" <<'PY'
import ast, operator, sys

raw = sys.argv[1].strip()
expr = raw.replace("×", "*").replace("÷", "/")

BIN_OPS = {
    ast.Add: operator.add, ast.Sub: operator.sub,
    ast.Mult: operator.mul, ast.Div: operator.truediv,
    ast.Mod: operator.mod,
}
UNARY_OPS = {ast.UAdd: operator.pos, ast.USub: operator.neg}

def eval_node(node):
    if isinstance(node, ast.Expression):
        return eval_node(node.body)
    if isinstance(node, ast.Constant):
        if isinstance(node.value, (int, float)):
            return node.value
        raise ValueError(f"invalid constant: {node.value!r}")
    if isinstance(node, ast.UnaryOp) and type(node.op) in UNARY_OPS:
        return UNARY_OPS[type(node.op)](eval_node(node.operand))
    if isinstance(node, ast.BinOp) and type(node.op) in BIN_OPS:
        return BIN_OPS[type(node.op)](eval_node(node.left), eval_node(node.right))
    raise ValueError("invalid expression — only + - * / % and () allowed")

try:
    tree = ast.parse(expr, mode="eval")
    value = eval_node(tree)
    if isinstance(value, float) and value.is_integer():
        value = int(value)
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
[[ -z "${result:-}" ]] && exit 1

if [[ "$result" == Error:* ]]; then
    notify-send "Calculator" "$result" 2>/dev/null || true
    exit 1
fi

# Result menu — show value, select to copy
choice="$(printf '%s\n' "$result" | rofi -dmenu -i -p "Result" -config "$ROFI_CONFIG")"
[[ -z "${choice:-}" ]] && exit 0

printf '%s' "$choice" | wl-copy
notify-send "Calculator" "Copied: $choice" 2>/dev/null || true
