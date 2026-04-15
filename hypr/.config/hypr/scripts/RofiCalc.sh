#!/usr/bin/env bash
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
        -mesg "Examples: 1+1, 1 + 1, (8*3)-2, 2**8" \
        -config "$ROFI_CONFIG"
)"

[[ -z "${expr:-}" ]] && exit 0

result="$(
python3 - "$expr" <<'PY'
import ast
import operator
import sys

expr = sys.argv[1].strip()

expr = expr.replace("×", "*").replace("÷", "/").replace("^", "**")

OPS = {
    ast.Add: operator.add,
    ast.Sub: operator.sub,
    ast.Mult: operator.mul,
    ast.Div: operator.truediv,
    ast.FloorDiv: operator.floordiv,
    ast.Mod: operator.mod,
    ast.Pow: operator.pow,
    ast.UAdd: operator.pos,
    ast.USub: operator.neg,
}

def eval_node(node):
    if isinstance(node, ast.Expression):
        return eval_node(node.body)

    if isinstance(node, ast.Constant):
        if isinstance(node.value, (int, float)):
            return node.value
        raise ValueError("invalid constant")

    if isinstance(node, ast.UnaryOp) and type(node.op) in OPS:
        return OPS[type(node.op)](eval_node(node.operand))

    if isinstance(node, ast.BinOp) and type(node.op) in OPS:
        return OPS[type(node.op)](eval_node(node.left), eval_node(node.right))

    raise ValueError("invalid expression")

try:
    tree = ast.parse(expr, mode="eval")
    value = eval_node(tree)

    if isinstance(value, float) and value.is_integer():
        value = int(value)

    print(value)
except ZeroDivisionError:
    print("Error: division by zero")
    sys.exit(1)
except Exception:
    print("Error: invalid expression")
    sys.exit(1)
PY
)" || true

[[ -z "${result:-}" ]] && exit 1

if [[ "$result" == Error:* ]]; then
    notify-send "Calculator" "$result" 2>/dev/null || true
    exit 1
fi

choice="$(
    printf '%s\n%s = %s\n' "Copy result" "$expr" "$result" |
    rofi -dmenu \
        -i \
        -p "Result" \
        -config "$ROFI_CONFIG"
)"
[[ -z "${result:-}" ]] && exit 1

if [[ "$result" == Error:* ]]; then
    notify-send "Calculator" "$result" 2>/dev/null || true
    exit 1
fi

printf '%s' "$result" | wl-copy
notify-send "Calculator" "Copied: $result" 2>/dev/null || true
