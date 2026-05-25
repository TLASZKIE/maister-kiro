#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CORE="$ROOT/plugins/maister"
OUT="$ROOT/output/kiro-cli"

# Cross-platform sed in-place
sedi() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

rm -rf "$OUT"
mkdir -p "$OUT/.kiro/skills" "$OUT/.kiro/agents" "$OUT/.kiro/steering" "$OUT/.kiro/settings"

# ─── 1. Copy skills (already SKILL.md format, compatible with Kiro CLI) ───
cp -r "$CORE/skills/"* "$OUT/.kiro/skills/"

# ─── 2. Convert commands to skills (Kiro CLI has no separate commands concept) ───
# Commands become skills since Kiro skills ARE slash commands
for cmd in "$CORE/commands/"*.md; do
  [ -f "$cmd" ] || continue
  basename=$(basename "$cmd" .md)
  mkdir -p "$OUT/.kiro/skills/$basename"
  cp "$cmd" "$OUT/.kiro/skills/$basename/SKILL.md"
done

# ─── 3. Copy agents as reference files accessible to skills ───
mkdir -p "$OUT/.kiro/agents/references"
cp "$CORE/agents/"*.md "$OUT/.kiro/agents/references/"

# ─── 4. Strip maister: prefix from skill names ───
find "$OUT/.kiro/skills" -name "SKILL.md" | while read f; do
  sedi 's/^name: maister:/name: maister-/' "$f"
done

# ─── 5. Replace maister: prefix with maister- in all references ───
find "$OUT/.kiro" -name "*.md" | while read f; do
  sedi 's/maister:/maister-/g' "$f"
done

# ─── 6. Replace CLAUDE.md references with Kiro steering equivalent ───
find "$OUT/.kiro/skills" -name "*.md" | while read f; do
  sedi 's/CLAUDE\.md/.kiro\/steering\/maister.md/g' "$f"
done

# ─── 7. Replace AskUserQuestion tool references with direct-ask pattern ───
# Kiro CLI has no ask_user tool — the agent asks questions directly in its response
# and waits for the user's next message. Replace tool invocation language with direct-ask.
find "$OUT/.kiro" -name "*.md" | while read f; do
  sedi \
    -e 's/Invoke `AskUserQuestion` now/Ask the user directly in your response now (present options as a numbered list and STOP — wait for their reply)/g' \
    -e 's/invoke `AskUserQuestion`/ask the user directly in your response (present options as a numbered list and STOP — wait for their reply)/g' \
    -e 's/invoke the `AskUserQuestion` tool/ask the user directly in your response (present options as a numbered list and STOP — wait for their reply)/g' \
    -e 's/Use `AskUserQuestion`/Ask the user directly in your response/g' \
    -e 's/use `AskUserQuestion`/ask the user directly in your response/g' \
    -e 's/USE AskUserQuestion/ASK THE USER directly in your response/g' \
    -e 's/use AskUserQuestion/ask the user directly in your response/g' \
    -e 's/Use AskUserQuestion/Ask the user directly in your response/g' \
    -e 's/`AskUserQuestion` tool/direct question in your response/g' \
    -e 's/AskUserQuestion tool/direct question in your response/g' \
    -e 's/`AskUserQuestion`/a direct question to the user/g' \
    -e 's/AskUserQuestion/a direct question to the user/g' \
    "$f"
done

# ─── 8. Transform multi-select patterns to sequential ───
find "$OUT/.kiro/skills" -name "*.md" | while read f; do
  sedi \
    -e 's/multi-select question/sequential single-select questions (one per option)/g' \
    -e 's/multi-select/sequential single-select/g' \
    -e 's/multiselect/sequential single-select/g' \
    -e 's/multiSelect/sequential single-select/g' \
    "$f"
done

# ─── 9. Create steering file from CLAUDE.md ───
cp "$CORE/CLAUDE.md" "$OUT/.kiro/steering/maister.md"

# ─── 9b. Apply same transformations to steering file (created after steps 5-7) ───
sedi 's/maister:/maister-/g' "$OUT/.kiro/steering/maister.md"
sedi 's/CLAUDE\.md/.kiro\/steering\/maister.md/g' "$OUT/.kiro/steering/maister.md"
sedi \
  -e 's/Invoke `AskUserQuestion` now/Ask the user directly in your response now (present options as a numbered list and STOP — wait for their reply)/g' \
  -e 's/invoke `AskUserQuestion`/ask the user directly in your response (present options as a numbered list and STOP — wait for their reply)/g' \
  -e 's/invoke the `AskUserQuestion` tool/ask the user directly in your response (present options as a numbered list and STOP — wait for their reply)/g' \
  -e 's/Use `AskUserQuestion`/Ask the user directly in your response/g' \
  -e 's/use `AskUserQuestion`/ask the user directly in your response/g' \
  -e 's/USE AskUserQuestion/ASK THE USER directly in your response/g' \
  -e 's/use AskUserQuestion/ask the user directly in your response/g' \
  -e 's/Use AskUserQuestion/Ask the user directly in your response/g' \
  -e 's/`AskUserQuestion` tool/direct question in your response/g' \
  -e 's/AskUserQuestion tool/direct question in your response/g' \
  -e 's/`AskUserQuestion`/a direct question to the user/g' \
  -e 's/AskUserQuestion/a direct question to the user/g' \
  "$OUT/.kiro/steering/maister.md"

# ─── 9c. Append Platform: Kiro CLI section AFTER transformations ───
cat >> "$OUT/.kiro/steering/maister.md" << 'EOF'

## Platform: Kiro CLI

This is the Kiro CLI variant. Key differences from Claude Code:
- **No multi-select**: When asking users to select multiple options, ask sequential single-select questions instead
- **Skill names**: Use `maister-` prefix (e.g., `maister-development`); skills double as slash commands in Kiro CLI
- **Project instructions**: Use `.kiro/steering/` files instead of `CLAUDE.md`
- **No ask_user tool**: Kiro CLI does NOT have an `ask_user` or `AskUserQuestion` tool. To ask the user a question, simply write the question directly in your response text with numbered options and STOP. Wait for the user's next message as their answer. This applies to all MANDATORY GATEs, phase transitions, and clarifying questions.
- **Subagents**: Agent definitions are in `.kiro/agents/references/` — reference them by filename
- **Hooks**: Defined in the agent JSON config, not as separate shell scripts
EOF

# ─── 10. Create the main maister agent config ───
cat > "$OUT/.kiro/agents/maister.json" << 'EOF'
{
  "name": "maister",
  "description": "Structured, standards-aware development workflows — guided features, bug fixes, research, migrations, and more",
  "prompt": "file://../steering/maister.md",
  "tools": ["*"],
  "allowedTools": ["read", "write", "shell", "knowledge"],
  "resources": [
    "skill://.kiro/skills/**/SKILL.md",
    "file://.kiro/steering/**/*.md",
    "file://.kiro/agents/references/**/*.md"
  ],
  "hooks": {
    "userPromptSubmit": [
      {
        "command": "echo '{\"additionalContext\": \"MAISTER PLUGIN RULE: When any /maister-* slash command appears, follow the skill instructions exactly. Do not substitute your own approach. Complexity assessment is the workflow job, not yours. At every MANDATORY GATE checkpoint, ask the user directly in your response (present options as a numbered list and STOP to wait for their reply) regardless of permission mode.\"}'"
      }
    ],
    "preToolUse": [
      {
        "matcher": "shell",
        "command": "bash -c 'INPUT=$(cat); CMD=$(echo \"$INPUT\" | grep -oP \"\\\"command\\\":\\s*\\\"\\K[^\\\"]+\" 2>/dev/null || true); if echo \"$CMD\" | grep -qEi \"git\\s+stash|git\\s+reset\\s+--hard|git\\s+checkout\\s+--\\s+\\.|git\\s+clean|git\\s+push\\s+(-f|--force)|rm\\s+-rf\"; then echo \"Destructive command blocked\" >&2; exit 2; fi'"
      }
    ]
  },
  "mcpServers": {
    "playwright": {
      "command": "npx",
      "args": ["@playwright/mcp@latest"]
    }
  },
  "welcomeMessage": "Maister ready. Use /maister-development, /maister-research, /maister-init, or just describe your task."
}
EOF

# ─── 11. Create MCP settings ───
cp "$CORE/.mcp.json" "$OUT/.kiro/settings/mcp.json"

# ─── 12. Remove hooks directory (not used in Kiro CLI — hooks are in agent config) ───
rm -rf "$OUT/.kiro/skills/hooks" 2>/dev/null || true

echo "Built Kiro CLI variant at $OUT"
echo ""
echo "To use: copy $OUT/.kiro/ into your project root, then run:"
echo "  kiro-cli --agent maister"
