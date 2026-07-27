# ============================================================================
# Shared assembly for build-* scripts.
#
# Source this (do not execute) after defining:
#   MODEL_NAME   model tag to create
#   BASE_MODEL   base model to FROM
#   EXTRAS       array of Modelfile directives (TEMPLATE/RENDERER/PARSER)
#   PARAMS       array of "<name> <value>" sampling params
# ============================================================================

AI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Preflight: fail loudly if the base model isn't pulled. Without this the script
# assembles the whole prompt, writes system.txt/Modelfile, and only dies at
# `ollama create` — leaving stale artifacts that look like a successful build.
if ! ollama list 2>/dev/null | awk 'NR>1 {print $1}' | grep -qxF "$BASE_MODEL"; then
  echo "ERROR: base model '$BASE_MODEL' is not pulled." >&2
  echo "  Pull it:      ollama pull $BASE_MODEL" >&2
  echo "  Or retarget:  edit BASE_MODEL in $(basename "$0")" >&2
  echo "  Installed:" >&2
  ollama list 2>/dev/null | awk 'NR>1 {print "    " $1}' >&2
  exit 1
fi

OUT_DIR="$AI_ROOT/models/$MODEL_NAME"
SYSTEM_FILE="$OUT_DIR/system.txt"
MODELFILE="$OUT_DIR/Modelfile"
mkdir -p "$OUT_DIR"

{
  echo "=== SYSTEM METADATA ==="
  echo "Model: $MODEL_NAME"
  echo "Base:  $BASE_MODEL"
  echo "Built: $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  echo

  # Inject reference first, user context second, behavior rules last.
  for dir in "$AI_ROOT/knowledge" "$AI_ROOT/memory" "$AI_ROOT/prompts"; do
    find "$dir" -type f -name '*.md' -size -100k -print0 2>/dev/null \
      | sort -z \
      | while IFS= read -r -d '' f; do
          rel="${f#"$AI_ROOT/"}"
          echo "--- START FILE: $rel ---"
          awk 1 "$f"   # like cat, but guarantees a trailing newline so the
                       # END marker never glues onto a file's last line
          echo "--- END FILE: $rel ---"
          echo
        done
  done
} > "$SYSTEM_FILE"

if grep -q '"""' "$SYSTEM_FILE"; then
  echo "ERROR: assembled prompt contains triple-quotes; would break Modelfile parsing." >&2
  exit 1
fi

{
  echo "FROM $BASE_MODEL"
  for line in "${EXTRAS[@]}"; do echo "$line"; done
  echo
  echo 'SYSTEM """'
  # Strip per-file provenance markers from what the model receives — it recites
  # them ("Constraints from prompts/..."); they exist only for human debugging
  # in system.txt. Markdown headers in each file preserve section structure.
  grep -vE '^--- (START|END) FILE: .* ---$' "$SYSTEM_FILE"
  echo '"""'
  echo
  for p in "${PARAMS[@]}"; do echo "PARAMETER $p"; done
} > "$MODELFILE"

ollama create "$MODEL_NAME" -f "$MODELFILE"

echo
echo "✓ Built $MODEL_NAME from $BASE_MODEL"
echo "  System prompt: $(wc -l < "$SYSTEM_FILE") lines, $(wc -w < "$SYSTEM_FILE") words"
echo "  Modelfile:     $MODELFILE"
