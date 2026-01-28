#!/bin/bash

# ============================================================
# MAKER Framework - Voting Script with LLM-as-Judge + Testing
# Based on "Solving a Million-Step LLM Task with Zero Errors"
# ============================================================

set -e

# Configuration
K=3                      # Winner needs K votes ahead of runner-up
SAMPLES_PER_ROUND=5      # Number of code generation calls per round
JUDGE_CALLS_PER_ROUND=5  # Number of judge calls per round
MAX_SAMPLES_FOR_JUDGE=10 # Cap samples shown to judge
MAX_TOKENS=750           # Red-flag threshold
MAX_FIX_ATTEMPTS=10      # Max attempts to fix failing code
OUTPUT_FILE=""           # Will be auto-extracted from task file
WORKSPACE_DIR="./maker_workspace"

# Task file (from command-line argument or default)
TASK_FILE="${1:-task.txt}"

# Context file (hard-coded)
CONTEXT_FILE="GLOBAL_CONTEXT.md"

# Clean workspace from previous runs
rm -rf "$WORKSPACE_DIR"
mkdir -p "$WORKSPACE_DIR/samples"

SAMPLES_DIR="$WORKSPACE_DIR/samples"
VOTES_FILE="$WORKSPACE_DIR/votes.txt"

# Read task from external file
if [[ ! -f "$TASK_FILE" ]]; then
    echo "Error: Task file '$TASK_FILE' not found."
    echo "Usage: $0 [task_file]"
    echo "  task_file: Path to a file containing the task prompt (default: task.txt)"
    exit 1
fi

# Print files being read
echo "Reading files:"
echo "  Context: $CONTEXT_FILE"
echo "  Task:    $TASK_FILE"
echo ""

# Read context file if it exists
GLOBAL_CONTEXT=""
if [[ -f "$CONTEXT_FILE" ]]; then
    GLOBAL_CONTEXT=$(cat "$CONTEXT_FILE")
    echo "  ✓ Loaded context file: $CONTEXT_FILE"
else
    echo "  ✗ Context file not found: $CONTEXT_FILE"
fi

# Build the full prompt with context + task
TASK_CONTENT=$(cat "$TASK_FILE")
echo "  ✓ Loaded task file: $TASK_FILE"

# Auto-extract output filename from task content
extract_output_filename() {
    local content="$1"
    local filename=""

    # Pattern 1: "**File:**" or "File:" followed by backticked path
    # e.g., **File:** `lib/core/database/helpers/identity_db_helpers.dart`
    filename=$(echo "$content" | grep -oE '\*?\*?File:\*?\*?\s*`[a-zA-Z0-9_./-]+\.(dart|js|ts|sql|py|md|json|yaml|yml|sh|txt|swift|kt|java|go|rs|c|cpp|h|hpp)`' | head -1 | grep -oE '`[^`]+`' | tr -d '`' | xargs basename 2>/dev/null)

    # Pattern 2: "File: path/to/filename.ext" without backticks
    if [[ -z "$filename" ]]; then
        filename=$(echo "$content" | grep -oE 'File:\s*[a-zA-Z0-9_./-]+\.(dart|js|ts|sql|py|md|json|yaml|yml|sh|txt|swift|kt|java|go|rs|c|cpp|h|hpp)' | head -1 | sed 's/File:\s*//' | xargs basename 2>/dev/null)
    fi

    # Pattern 3: Filenames in backticks like `filename.ext` (simple name, not path)
    if [[ -z "$filename" ]]; then
        filename=$(echo "$content" | grep -oE '\`[a-zA-Z0-9_.-]+\.(dart|js|ts|sql|py|md|json|yaml|yml|sh|txt|swift|kt|java|go|rs|c|cpp|h|hpp)\`' | head -1 | tr -d '`')
    fi

    # Pattern 4: "Output: filename.ext" or "Deliverable: filename.ext"
    if [[ -z "$filename" ]]; then
        filename=$(echo "$content" | grep -oE '(Output|Deliverable):\s*[a-zA-Z0-9_.-]+\.(dart|js|ts|sql|py|md|json|yaml|yml|sh|txt)' | head -1 | sed 's/^[^:]*:\s*//')
    fi

    echo "$filename"
}

EXTRACTED_FILE=$(extract_output_filename "$TASK_CONTENT")
if [[ -n "$EXTRACTED_FILE" ]]; then
    OUTPUT_FILE="$EXTRACTED_FILE"
    echo "  ✓ Auto-detected output file: $OUTPUT_FILE"
else
    OUTPUT_FILE="output.txt"
    echo "  ⚠ No output filename found, using default: $OUTPUT_FILE"
fi
echo ""

# Build full prompt with explicit code block instructions
CODE_BLOCK_INSTRUCTION="

---

## CRITICAL OUTPUT REQUIREMENT

You MUST output ONLY a code block. No explanations before or after.
Do NOT check if files exist. Always generate fresh code.
Format your ENTIRE response as:

\`\`\`
[your complete code here]
\`\`\`

Nothing else. Just the code block."

if [[ -n "$GLOBAL_CONTEXT" ]]; then
    TASK_PROMPT="## Global Context

$GLOBAL_CONTEXT

---

## Task

$TASK_CONTENT
$CODE_BLOCK_INSTRUCTION"
else
    TASK_PROMPT="$TASK_CONTENT
$CODE_BLOCK_INSTRUCTION"
fi

# Confusion phrases that trigger red-flag
CONFUSION_PHRASES=(
    "I'm not sure"
    "I don't know"
    "I think maybe"
    "let me reconsider"
    "I cannot"
    "I can't"
)

# Track sample count
SAMPLE_COUNT=0

echo "============================================================"
echo "MAKER Framework - Voting System with LLM-as-Judge"
echo "============================================================"
echo "Configuration:"
echo "  Output file: $OUTPUT_FILE"
echo "  K (margin needed): $K"
echo "  Samples per round: $SAMPLES_PER_ROUND"
echo "  Judge calls per round: $JUDGE_CALLS_PER_ROUND"
echo "  Max samples for judge: $MAX_SAMPLES_FOR_JUDGE"
echo "  Max tokens: $MAX_TOKENS"
echo "  Max fix attempts: $MAX_FIX_ATTEMPTS"
echo "  Workspace: $WORKSPACE_DIR"
echo "============================================================"
echo ""

# ------------------------------------------------------------
# Function: Extract code block from response
# Supports any language: ```sql, ```dart, ```javascript, etc.
# ------------------------------------------------------------
extract_code_block() {
    local response="$1"
    echo "$response" | sed -n '/^```/,/^```/p' | sed '1d;$d'
}

# ------------------------------------------------------------
# Function: Check for confusion phrases
# ------------------------------------------------------------
has_confusion() {
    local response="$1"
    local response_lower=$(echo "$response" | tr '[:upper:]' '[:lower:]')
    
    for phrase in "${CONFUSION_PHRASES[@]}"; do
        local phrase_lower=$(echo "$phrase" | tr '[:upper:]' '[:lower:]')
        if [[ "$response_lower" == *"$phrase_lower"* ]]; then
            echo "$phrase"
            return 0
        fi
    done
    return 1
}

# ------------------------------------------------------------
# Function: Count tokens (words) in text
# ------------------------------------------------------------
count_tokens() {
    local text="$1"
    echo "$text" | wc -w | tr -d ' '
}

# ------------------------------------------------------------
# Function: Red-flag check
# Returns 0 if valid, 1 if should be discarded
# ------------------------------------------------------------
red_flag_check() {
    local response="$1"
    local sample_num="$2"
    
    # Check 1: Does it have a code block?
    local code_block=$(extract_code_block "$response")
    if [[ -z "$code_block" ]]; then
        echo "  ✗ Sample $sample_num: RED FLAG - No code block found"
        return 1
    fi
    
    # Check 2: Is the code block too long?
    local token_count=$(count_tokens "$code_block")
    if [[ $token_count -gt $MAX_TOKENS ]]; then
        echo "  ✗ Sample $sample_num: RED FLAG - Too long ($token_count tokens)"
        return 1
    fi
    
    # Check 3: Contains confusion phrases?
    local confusion=$(has_confusion "$response")
    if [[ -n "$confusion" ]]; then
        echo "  ✗ Sample $sample_num: RED FLAG - Confusion detected: '$confusion'"
        return 1
    fi
    
    echo "  ✓ Sample $sample_num: Valid ($token_count tokens)"
    return 0
}

# ------------------------------------------------------------
# Function: Get top N samples by vote count
# ------------------------------------------------------------
get_top_samples() {
    local max_count="$1"
    
    local sample_files=("$SAMPLES_DIR"/sample_*.txt)
    
    if [[ ! -f "$VOTES_FILE" ]] || [[ ! -s "$VOTES_FILE" ]]; then
        # No votes yet, return first N samples
        for f in "${sample_files[@]}"; do
            if [[ -f "$f" ]]; then
                basename "$f" .txt | sed 's/sample_//'
            fi
        done | head -n "$max_count"
        return
    fi

    # Count votes per sample and sort
    for f in "${sample_files[@]}"; do
        if [[ -f "$f" ]]; then
            local id=$(basename "$f" .txt | sed 's/sample_//')
            local votes=$(grep -c "^${id}$" "$VOTES_FILE" 2>/dev/null || echo "0")
            echo "$votes $id"
        fi
    done | sort -rn | head -n "$max_count" | awk '{print $2}'
}

# ------------------------------------------------------------
# Function: Build judge prompt with samples
# ------------------------------------------------------------
build_judge_prompt() {
    local sample_ids=("$@")
    local prompt="You are a code review judge.

Original task:
$TASK_PROMPT

Here are ${#sample_ids[@]} code samples. Which one best solves the task?

"
    
    local i=1
    for id in "${sample_ids[@]}"; do
        local code=$(cat "$SAMPLES_DIR/sample_${id}.txt")
        prompt+="Sample $i (ID: $id):
\`\`\`
$code
\`\`\`

"
        ((i++))
    done
    
    prompt+="Consider: correctness, completeness, follows requirements.

Answer with ONLY the sample ID (e.g., $( IFS=', '; echo "${sample_ids[*]}" )). Nothing else."
    
    echo "$prompt"
}

# ------------------------------------------------------------
# Function: Run code generation for one round
# ------------------------------------------------------------
run_generation_round() {
    local round_num="$1"
    echo ""
    echo "────────────────────────────────────────────────────────────"
    echo "Round $round_num: Generating $SAMPLES_PER_ROUND code samples..."
    echo "────────────────────────────────────────────────────────────"
    
    # Run samples in parallel
    local pids=()
    local start_id=$((SAMPLE_COUNT + 1))
    
    # Write prompt to file to avoid shell escaping issues
    local prompt_file="$WORKSPACE_DIR/prompt.txt"
    echo "$TASK_PROMPT" > "$prompt_file"

    for i in $(seq 1 $SAMPLES_PER_ROUND); do
        local sample_id=$((start_id + i - 1))
        local response_file="$WORKSPACE_DIR/response_${sample_id}.txt"
        local error_file="$WORKSPACE_DIR/error_${sample_id}.txt"
        (cat "$prompt_file" | claude -p - --dangerously-skip-permissions > "$response_file" 2>"$error_file") &
        pids+=($!)
    done
    
    # Wait for all to complete
    echo "  Waiting for $SAMPLES_PER_ROUND LLM calls to complete..."
    for pid in "${pids[@]}"; do
        wait $pid 2>/dev/null || true
    done
    echo "  All calls completed."
    echo ""
    
    # Process each response
    echo "  Filtering responses:"
    local valid_count=0
    
    for i in $(seq 1 $SAMPLES_PER_ROUND); do
        local sample_id=$((start_id + i - 1))
        local response_file="$WORKSPACE_DIR/response_${sample_id}.txt"
        
        if [[ ! -f "$response_file" ]]; then
            echo "  ✗ Sample $sample_id: RED FLAG - No response file"
            continue
        fi
        
        local response=$(cat "$response_file")
        
        if red_flag_check "$response" "$sample_id"; then
            # Valid response - extract and store code
            local code_block=$(extract_code_block "$response")
            echo "$code_block" > "$SAMPLES_DIR/sample_${sample_id}.txt"
            ((valid_count++))
            ((SAMPLE_COUNT++))
        fi
    done

    echo ""
    echo "  Valid samples this round: $valid_count"
    echo "  Total samples in pool: $(ls -1 "$SAMPLES_DIR"/sample_*.txt 2>/dev/null | wc -l)"
}

# ------------------------------------------------------------
# Function: Run judge voting for one round
# ------------------------------------------------------------
run_judge_round() {
    local round_num="$1"
    
    echo ""
    echo "  Running $JUDGE_CALLS_PER_ROUND judge evaluations..."
    
    # Get top samples to show judge
    local top_samples=($(get_top_samples $MAX_SAMPLES_FOR_JUDGE))
    
    if [[ ${#top_samples[@]} -lt 2 ]]; then
        echo "  Not enough samples to judge yet."
        return
    fi
    
    echo "  Samples being judged: ${top_samples[*]}"
    
    # Build judge prompt
    local judge_prompt=$(build_judge_prompt "${top_samples[@]}")
    
    # Run judge calls in parallel
    local pids=()
    for i in $(seq 1 $JUDGE_CALLS_PER_ROUND); do
        local judge_file="$WORKSPACE_DIR/judge_${round_num}_${i}.txt"
        (codex exec "$judge_prompt" --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check --model gpt-5.1-codex-max > "$judge_file" 2>/dev/null) &
        pids+=($!)
    done
    
    # Wait for all judges
    echo "  Waiting for judge responses..."
    for pid in "${pids[@]}"; do
        wait $pid 2>/dev/null || true
    done
    
    # Process judge responses
    echo "  Judge votes:"
    for i in $(seq 1 $JUDGE_CALLS_PER_ROUND); do
        local judge_file="$WORKSPACE_DIR/judge_${round_num}_${i}.txt"

        if [[ -f "$judge_file" ]] && [[ -s "$judge_file" ]]; then
            local raw_response=$(cat "$judge_file")
            local vote=""

            # Try to extract sample ID from response
            # First try: exact match after stripping whitespace
            vote=$(echo "$raw_response" | tr -d '[:space:]')

            # Second try: look for sample ID pattern in the response
            local valid_vote=""
            for id in "${top_samples[@]}"; do
                if [[ "$vote" == "$id" ]]; then
                    valid_vote="$id"
                    break
                fi
                # Also check if ID appears anywhere in response (e.g., "Sample 5" or "I choose 5")
                if echo "$raw_response" | grep -qE "(^|[^0-9])${id}([^0-9]|$)"; then
                    valid_vote="$id"
                    break
                fi
            done

            if [[ -n "$valid_vote" ]]; then
                echo "$valid_vote" >> "$VOTES_FILE"
                echo "    Judge $i voted for: Sample $valid_vote"
            else
                # Log the actual response for debugging
                local truncated=$(echo "$raw_response" | head -c 50 | tr '\n' ' ')
                echo "    Judge $i: Invalid vote '$truncated...' (skipped)"
            fi
        else
            echo "    Judge $i: No response (skipped)"
        fi
    done
}

# ------------------------------------------------------------
# Function: Check for winner
# Returns 0 if winner found, 1 otherwise
# Sets WINNER_ID global variable
# ------------------------------------------------------------
check_for_winner() {
    echo ""
    echo "  Counting votes..."
    
    if [[ ! -s "$VOTES_FILE" ]]; then
        echo "  No valid votes yet."
        return 1
    fi
    
    # Count votes for each sample
    local vote_counts=$(sort "$VOTES_FILE" | uniq -c | sort -rn)
    
    echo ""
    echo "  Current standings:"
    echo "$vote_counts" | head -5 | while read count id; do
        echo "    Sample $id: $count votes"
    done
    
    # Get top two vote counts
    local first_line=$(echo "$vote_counts" | head -1)
    local second_line=$(echo "$vote_counts" | sed -n '2p')

    local first_count=$(echo "$first_line" | awk '{print $1}')
    local first_id=$(echo "$first_line" | awk '{print $2}')

    # Handle case where there's only one candidate
    local second_count=0
    if [[ -n "$second_line" ]]; then
        second_count=$(echo "$second_line" | awk '{print $1}')
    fi
    
    local margin=$((first_count - second_count))
    
    echo ""
    echo "  Leader: Sample $first_id with $first_count votes"
    echo "  Margin: $margin (need $K to win)"
    
    if [[ $margin -ge $K ]]; then
        WINNER_ID="$first_id"
        return 0
    fi
    
    echo "  No winner yet. Continuing..."
    return 1
}

# ------------------------------------------------------------
# Function: Install missing packages based on language
# ------------------------------------------------------------
install_packages() {
    local lang="$1"
    shift
    local packages=("$@")

    if [[ ${#packages[@]} -eq 0 ]]; then
        return 0
    fi

    echo "  ℹ Installing missing packages..."

    case "$lang" in
        npm)
            # Initialize package.json if it doesn't exist
            if [[ ! -f "package.json" ]]; then
                echo "    Creating package.json..."
                npm init -y 2>/dev/null || true
            fi
            for pkg in "${packages[@]}"; do
                echo "    npm install $pkg"
                npm install "$pkg" --save 2>&1 | grep -v "^npm WARN" || true
            done
            ;;

        npm-dev)
            if [[ ! -f "package.json" ]]; then
                npm init -y 2>/dev/null || true
            fi
            for pkg in "${packages[@]}"; do
                echo "    npm install -D $pkg"
                npm install "$pkg" --save-dev 2>&1 | grep -v "^npm WARN" || true
            done
            ;;

        dart)
            # Create pubspec.yaml if it doesn't exist
            if [[ ! -f "pubspec.yaml" ]]; then
                echo "    Creating pubspec.yaml..."
                cat > pubspec.yaml << 'PUBSPEC'
name: maker_generated
description: Generated Dart project
version: 1.0.0

environment:
  sdk: '>=3.0.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
PUBSPEC
                echo "    ✓ Created pubspec.yaml"
                # Run flutter pub get to initialize
                if command -v flutter &> /dev/null; then
                    flutter pub get 2>&1 | tail -2 || true
                fi
            fi
            for pkg in "${packages[@]}"; do
                echo "    flutter pub add $pkg"
                if command -v flutter &> /dev/null; then
                    flutter pub add "$pkg" 2>&1 | grep -v "^Because" | head -3 || true
                else
                    dart pub add "$pkg" 2>&1 | head -3 || true
                fi
            done
            ;;

        pip)
            for pkg in "${packages[@]}"; do
                echo "    pip install $pkg"
                pip3 install "$pkg" 2>&1 | tail -2 || true
            done
            ;;
    esac

    echo "  ✓ Package installation completed"
}

# ------------------------------------------------------------
# Function: Compile/Lint check based on file type
# Runs appropriate compiler or linter for the file type
# ------------------------------------------------------------
compile_check() {
    echo ""
    echo "  Running compile/lint check..."

    local file_ext="${OUTPUT_FILE##*.}"
    local compile_output=""
    local exit_code=0

    case "$file_ext" in
        ts)
            echo "  File type: TypeScript (.ts)"
            if command -v tsc &> /dev/null; then
                # First run - check for errors
                local raw_output=$(tsc --noEmit --strict --skipLibCheck --module ESNext --target ES2020 --moduleResolution node "$OUTPUT_FILE" 2>&1)

                # Check for missing modules and install them
                if echo "$raw_output" | grep -q "TS2307: Cannot find module"; then
                    # Extract npm package names (not local files starting with . or ..)
                    local npm_packages=$(echo "$raw_output" | grep "TS2307: Cannot find module" | grep -oE "'[^']+'" | tr -d "'" | grep -v "^\." | sort -u)

                    if [[ -n "$npm_packages" ]]; then
                        install_packages "npm" $npm_packages
                    fi

                    # Install @types/node if Buffer is missing
                    if echo "$raw_output" | grep -q "TS2580.*Buffer\|TS2580.*process"; then
                        install_packages "npm-dev" "@types/node"
                    fi

                    echo "  ℹ Re-running compile check..."
                    raw_output=$(tsc --noEmit --strict --skipLibCheck --module ESNext --target ES2020 --moduleResolution node "$OUTPUT_FILE" 2>&1)
                fi

                # Filter out local file errors (other task files)
                compile_output=$(echo "$raw_output" | grep "error TS" | grep -v "TS2307.*'\.\." | grep -v "TS2307.*'\./" | grep -v "TS2307")

                if [[ -n "$compile_output" ]]; then
                    exit_code=1
                else
                    # Show local file warnings
                    if echo "$raw_output" | grep -q "TS2307.*'\.\|TS2307.*'\.\."; then
                        echo "  ⚠ Local imports pending (other tasks):"
                        echo "$raw_output" | grep "TS2307.*'\." | head -3 | sed 's/^/    /'
                    fi
                    exit_code=0
                fi
            else
                echo "  ⚠ tsc not found, skipping TypeScript check"
                return 0
            fi
            ;;

        dart)
            echo "  File type: Dart (.dart)"
            if command -v dart &> /dev/null; then
                local raw_output=$(dart analyze "$OUTPUT_FILE" 2>&1)

                # Check for missing packages and try to install them
                # Error format: "... 'package:sqflite/sqflite.dart'. ... - uri_does_not_exist"
                if echo "$raw_output" | grep -q "package:.*uri_does_not_exist"; then
                    # Extract package names from errors like "'package:sqflite/sqflite.dart'"
                    local missing_packages=$(echo "$raw_output" | grep "uri_does_not_exist" | grep -oE "'package:[a-zA-Z0-9_]+/" | sed "s/'package://" | sed 's/\///' | sort -u)

                    if [[ -n "$missing_packages" ]]; then
                        install_packages "dart" $missing_packages
                    fi

                    echo "  ℹ Re-running analysis after installing packages..."
                    raw_output=$(dart analyze "$OUTPUT_FILE" 2>&1)
                fi

                # Filter out local file errors (other task files not generated yet)
                # These are errors for relative imports like '../../utils/flow_event_emitter.dart'
                compile_output=$(echo "$raw_output" | grep -v "uri_does_not_exist.*'\.\." | grep -v "uri_does_not_exist.*'\.")

                # Check for remaining errors (actual code issues)
                if echo "$compile_output" | grep -q "error •\|error -"; then
                    # Check if only undefined class/function from missing imports
                    local real_errors=$(echo "$compile_output" | grep "error" | grep -v "undefined_class\|undefined_function\|uri_does_not_exist")
                    if [[ -n "$real_errors" ]]; then
                        exit_code=1
                        compile_output="$real_errors"
                    else
                        # Only dependency-related errors - warn but pass
                        echo "  ⚠ Dependency warnings (packages or local files not available):"
                        echo "$raw_output" | grep "error -" | head -3 | sed 's/^/    /'
                        echo "  ℹ These will resolve when dependencies are installed/generated"
                        exit_code=0
                        compile_output=""
                    fi
                else
                    exit_code=0
                fi
            else
                echo "  ⚠ dart not found, skipping Dart analysis"
                return 0
            fi
            ;;

        js)
            echo "  File type: JavaScript (.js)"
            if command -v node &> /dev/null; then
                compile_output=$(node --check "$OUTPUT_FILE" 2>&1) && exit_code=0 || exit_code=$?
            else
                echo "  ⚠ node not found, skipping JavaScript syntax check"
                return 0
            fi
            ;;

        sql)
            echo "  File type: SQL (.sql)"
            # Basic SQL syntax check - just verify it's not empty and has SQL keywords
            if [[ -s "$OUTPUT_FILE" ]]; then
                if grep -qiE "CREATE|SELECT|INSERT|UPDATE|DELETE|ALTER|DROP" "$OUTPUT_FILE"; then
                    echo "  ✓ SQL file contains valid SQL keywords"
                    return 0
                else
                    compile_output="SQL file does not contain recognizable SQL statements"
                    exit_code=1
                fi
            else
                compile_output="SQL file is empty"
                exit_code=1
            fi
            ;;

        py)
            echo "  File type: Python (.py)"
            if command -v python3 &> /dev/null; then
                compile_output=$(python3 -m py_compile "$OUTPUT_FILE" 2>&1) && exit_code=0 || exit_code=$?
            else
                echo "  ⚠ python3 not found, skipping Python syntax check"
                return 0
            fi
            ;;

        go)
            echo "  File type: Go (.go)"
            if command -v go &> /dev/null; then
                compile_output=$(go build -o /dev/null "$OUTPUT_FILE" 2>&1) && exit_code=0 || exit_code=$?
            else
                echo "  ⚠ go not found, skipping Go compilation check"
                return 0
            fi
            ;;

        *)
            echo "  ⚠ Unknown file type (.$file_ext), skipping compile check"
            return 0
            ;;
    esac

    # Save compile output
    echo "$compile_output" > "$WORKSPACE_DIR/last_compile.txt"

    if [[ $exit_code -eq 0 ]]; then
        echo "  ✓ Compile/lint check PASSED"
        return 0
    else
        echo "  ✗ Compile/lint check FAILED"
        echo "$compile_output" | head -20 | sed 's/^/    /'
        TEST_ERROR="Compile/lint error: $compile_output"
        return 1
    fi
}

# ------------------------------------------------------------
# Function: Generate test file using Claude
# Creates appropriate tests based on the code and task
# ------------------------------------------------------------
generate_test_file() {
    local base_name="${OUTPUT_FILE%.*}"
    local file_ext="${OUTPUT_FILE##*.}"
    local test_file=""
    local test_framework=""

    # Determine test file name and framework based on language
    case "$file_ext" in
        ts)
            test_file="${base_name}.test.ts"
            test_framework="Use simple assertions with console.log for pass/fail. No external test framework needed. Exit with process.exit(1) on failure."
            ;;
        dart)
            test_file="${base_name}_test.dart"
            test_framework="Use the 'test' package. Import 'package:test/test.dart'."
            ;;
        js)
            test_file="${base_name}.test.js"
            test_framework="Use simple assertions with console.log for pass/fail. No external test framework needed. Exit with process.exit(1) on failure."
            ;;
        py)
            test_file="test_${base_name}.py"
            test_framework="Use unittest or simple assert statements."
            ;;
        *)
            echo "  ⚠ Cannot generate tests for .$file_ext files"
            return 1
            ;;
    esac

    echo "  Generating test file: $test_file"

    local current_code=$(cat "$OUTPUT_FILE")

    local test_prompt="Generate a test file for the following code.

TASK REQUIREMENTS:
$TASK_CONTENT

CODE TO TEST:
\`\`\`
$current_code
\`\`\`

TESTING INSTRUCTIONS:
- $test_framework
- Test the main function(s) with realistic inputs
- Test edge cases and error handling
- Mock any external dependencies (database, network, etc.)
- For Dart: mock Database with a fake that returns expected results
- Tests should be runnable standalone

CRITICAL: Output ONLY a code block with the complete test file. No explanations.
\`\`\`
[your complete test code here]
\`\`\`"

    # Write prompt to file
    local test_prompt_file="$WORKSPACE_DIR/test_prompt.txt"
    echo "$test_prompt" > "$test_prompt_file"

    local response=$(cat "$test_prompt_file" | claude -p - --dangerously-skip-permissions 2>/dev/null)
    local test_code=$(extract_code_block "$response")

    if [[ -z "$test_code" ]]; then
        echo "  ✗ Failed to generate test file"
        return 1
    fi

    echo "$test_code" > "$test_file"
    echo "  ✓ Generated test file: $test_file"

    # For Dart, ensure test package is available
    if [[ "$file_ext" == "dart" ]]; then
        if ! grep -q "test:" pubspec.yaml 2>/dev/null; then
            install_packages "dart" "test"
        fi
    fi

    echo "$test_file"
    return 0
}

# ------------------------------------------------------------
# Function: Run optional test file if exists
# Looks for a test file matching the output file name
# ------------------------------------------------------------
run_test_file() {
    echo ""
    echo "  Checking for test file..."

    local base_name="${OUTPUT_FILE%.*}"
    local file_ext="${OUTPUT_FILE##*.}"
    local test_file=""

    # Look for common test file patterns
    case "$file_ext" in
        ts)
            for pattern in "${base_name}.test.ts" "${base_name}_test.ts" "test_${base_name}.ts" "tests/${base_name}.test.ts"; do
                if [[ -f "$pattern" ]]; then
                    test_file="$pattern"
                    break
                fi
            done
            ;;
        dart)
            for pattern in "${base_name}_test.dart" "test/${base_name}_test.dart" "test_${base_name}.dart"; do
                if [[ -f "$pattern" ]]; then
                    test_file="$pattern"
                    break
                fi
            done
            ;;
        js)
            for pattern in "${base_name}.test.js" "${base_name}_test.js" "test_${base_name}.js"; do
                if [[ -f "$pattern" ]]; then
                    test_file="$pattern"
                    break
                fi
            done
            ;;
        py)
            for pattern in "test_${base_name}.py" "${base_name}_test.py" "tests/test_${base_name}.py"; do
                if [[ -f "$pattern" ]]; then
                    test_file="$pattern"
                    break
                fi
            done
            ;;
    esac

    # Generate test file if not found
    if [[ -z "$test_file" ]]; then
        echo "  ℹ No test file found, generating one..."
        test_file=$(generate_test_file)
        if [[ $? -ne 0 ]] || [[ -z "$test_file" ]]; then
            echo "  ⚠ Could not generate test file, skipping test execution"
            return 0
        fi
    fi

    echo "  Found test file: $test_file"
    echo "  Running tests..."

    local test_output=""
    local exit_code=0

    case "$file_ext" in
        ts)
            if command -v npx &> /dev/null; then
                test_output=$(npx ts-node "$test_file" 2>&1) && exit_code=0 || exit_code=$?
            fi
            ;;
        dart)
            if command -v dart &> /dev/null; then
                test_output=$(dart test "$test_file" 2>&1) && exit_code=0 || exit_code=$?
            fi
            ;;
        js)
            if command -v node &> /dev/null; then
                test_output=$(node "$test_file" 2>&1) && exit_code=0 || exit_code=$?
            fi
            ;;
        py)
            if command -v python3 &> /dev/null; then
                test_output=$(python3 "$test_file" 2>&1) && exit_code=0 || exit_code=$?
            fi
            ;;
    esac

    # Save test output
    echo "$test_output" > "$WORKSPACE_DIR/last_test.txt"

    if [[ $exit_code -eq 0 ]]; then
        echo "  ✓ Tests PASSED"
        return 0
    else
        echo "  ✗ Tests FAILED"
        echo "$test_output" | head -20 | sed 's/^/    /'
        TEST_ERROR="Test failure: $test_output"
        return 1
    fi
}

# ------------------------------------------------------------
# Function: Validate code using Claude
# Asks Claude to review the code against the task requirements
# ------------------------------------------------------------
validate_code() {
    echo ""
    echo "  Validating code against task requirements..."

    local current_code=$(cat "$OUTPUT_FILE")

    local validate_prompt="You are a code reviewer. Check if this code correctly implements the task.

TASK REQUIREMENTS:
$TASK_CONTENT

CODE TO VALIDATE:
\`\`\`
$current_code
\`\`\`

Review the code and check:
1. Does the code have correct syntax (no syntax errors)?
2. Does the code implement ALL requirements from the task?
3. Are there any obvious bugs or issues?

If the code is CORRECT and implements all requirements, respond with exactly:
VALIDATION_PASSED

If there are ANY issues, respond with:
VALIDATION_FAILED
[List each issue on a new line]

Be strict. Only pass if the code fully meets the requirements."

    # Write prompt to file to avoid shell escaping issues
    local validate_prompt_file="$WORKSPACE_DIR/validate_prompt.txt"
    echo "$validate_prompt" > "$validate_prompt_file"

    local response=$(cat "$validate_prompt_file" | claude -p - --dangerously-skip-permissions 2>/dev/null)

    # Save validation response
    echo "$response" > "$WORKSPACE_DIR/last_validation.txt"

    if echo "$response" | grep -q "VALIDATION_PASSED"; then
        echo "  ✓ Validation PASSED: Code meets requirements"
        return 0
    else
        echo "  ✗ Validation FAILED"
        # Extract issues after VALIDATION_FAILED
        echo "$response" | grep -A 100 "VALIDATION_FAILED" | tail -n +2 | head -20 | sed 's/^/    /'
        TEST_ERROR=$(echo "$response" | grep -A 100 "VALIDATION_FAILED" | tail -n +2 | head -10)
        return 1
    fi
}

# ------------------------------------------------------------
# Function: Run all tests
# Returns 0 if all pass, 1 if any fail
# Sets TEST_ERROR global variable with failure details
# ------------------------------------------------------------
run_all_tests() {
    echo ""
    echo "────────────────────────────────────────────────────────────"
    echo "Running Validation Pipeline..."
    echo "────────────────────────────────────────────────────────────"

    TEST_ERROR=""

    # Step 1: Compile/Lint check
    echo ""
    echo "  Step 1/2: Compile/Lint Check"
    if ! compile_check; then
        return 1
    fi

    # Step 2: Claude code review
    echo ""
    echo "  Step 2/2: Code Review (Claude)"
    if ! validate_code; then
        return 1
    fi

    echo ""
    echo "  ════════════════════════════════════════"
    echo "  ✓ ALL VALIDATION STEPS PASSED"
    echo "  ════════════════════════════════════════"
    return 0
}

# ------------------------------------------------------------
# Function: Get type definitions for a module from node_modules
# ------------------------------------------------------------
get_module_types() {
    local module_name="$1"
    local types=""

    # Try to find .d.ts file in node_modules
    local dts_file=""
    for path in \
        "node_modules/${module_name}/dist/index.d.ts" \
        "node_modules/${module_name}/dist/src/index.d.ts" \
        "node_modules/${module_name}/index.d.ts" \
        "node_modules/@types/${module_name}/index.d.ts"; do
        if [[ -f "$path" ]]; then
            dts_file="$path"
            break
        fi
    done

    if [[ -n "$dts_file" ]]; then
        # Extract exports (first 100 lines to avoid huge output)
        types=$(head -100 "$dts_file" 2>/dev/null)
    fi

    echo "$types"
}

# ------------------------------------------------------------
# Function: Fix failing code
# ------------------------------------------------------------
fix_code() {
    local attempt="$1"

    echo ""
    echo "────────────────────────────────────────────────────────────"
    echo "Fix Attempt $attempt of $MAX_FIX_ATTEMPTS"
    echo "────────────────────────────────────────────────────────────"

    local current_code=$(cat "$OUTPUT_FILE")
    local last_compile=$(cat "$WORKSPACE_DIR/last_compile.txt" 2>/dev/null || echo "")
    local last_validation=$(cat "$WORKSPACE_DIR/last_validation.txt" 2>/dev/null || echo "No validation output")

    # Extract module type info for modules with errors
    local type_context=""
    local file_ext="${OUTPUT_FILE##*.}"

    if [[ "$file_ext" == "ts" ]] && [[ -n "$last_compile" ]]; then
        # Extract module names from TS2305 (no exported member) and TS2339 (property doesn't exist) errors
        local problem_modules=$(echo "$last_compile" | grep -oE "Module '\"[^\"]+\"'" | grep -oE '@[a-zA-Z0-9_/-]+' | sort -u)

        if [[ -n "$problem_modules" ]]; then
            echo "  ℹ Fetching type definitions for problematic modules..."
            for mod in $problem_modules; do
                local mod_types=$(get_module_types "$mod")
                if [[ -n "$mod_types" ]]; then
                    echo "    Found types for: $mod"
                    type_context+="

TYPE DEFINITIONS FOR $mod:
\`\`\`typescript
$mod_types
\`\`\`"
                fi
            done
        fi
    fi

    # Build the fix prompt with additional context
    local extra_instructions=""
    if [[ -n "$type_context" ]]; then
        extra_instructions="
IMPORTANT: Use ONLY the exports shown in the type definitions below. Do NOT guess API names.
$type_context
"
    fi

    # Check if same errors are repeating
    if [[ $attempt -gt 2 ]]; then
        extra_instructions+="
WARNING: Previous fix attempts failed with the same errors. Try a DIFFERENT approach:
- Check actual package documentation
- Use alternative packages if needed
- Simplify the implementation
"
    fi

    local fix_prompt="The following code failed validation. Fix ALL the issues.

ORIGINAL TASK:
$TASK_CONTENT

CURRENT CODE:
\`\`\`
$current_code
\`\`\`

COMPILE ERRORS:
$last_compile

VALIDATION FEEDBACK:
$last_validation
$extra_instructions
Fix ALL the issues listed above. Make sure the code:
1. Has correct syntax
2. Implements ALL requirements from the original task
3. Addresses every compile error
4. Uses ONLY APIs that actually exist in the packages

CRITICAL: Output ONLY a code block. No explanations.
\`\`\`
[your complete fixed code here]
\`\`\`"

    echo "  Asking Claude to fix the code..."

    # Write prompt to file to avoid shell escaping issues
    local fix_prompt_file="$WORKSPACE_DIR/fix_prompt.txt"
    echo "$fix_prompt" > "$fix_prompt_file"

    local response=$(cat "$fix_prompt_file" | claude -p - --dangerously-skip-permissions 2>/dev/null)
    local code_block=$(extract_code_block "$response")

    if [[ -z "$code_block" ]]; then
        echo "  ✗ Failed to get fixed code"
        return 1
    fi

    echo "$code_block" > "$OUTPUT_FILE"
    echo "  ✓ Fixed code saved to: $OUTPUT_FILE"
    return 0
}

# ------------------------------------------------------------
# PHASE 1: Generate and Vote
# ------------------------------------------------------------
phase1_generate_and_vote() {
    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "PHASE 1: Generate and Vote"
    echo "════════════════════════════════════════════════════════════"
    
    local round=1
    local max_rounds=20  # Safety limit
    
    while [[ $round -le $max_rounds ]]; do
        # Generate code samples
        run_generation_round $round
        
        # Run judge voting
        run_judge_round $round
        
        # Check for winner
        if check_for_winner; then
            echo ""
            echo "════════════════════════════════════════════════════════════"
            echo "🏆 WINNER FOUND!"
            echo "════════════════════════════════════════════════════════════"
            echo "  Sample ID: $WINNER_ID"
            
            # Copy winner to output file
            cp "$SAMPLES_DIR/sample_${WINNER_ID}.txt" "$OUTPUT_FILE"
            echo "  ✓ Saved to: $OUTPUT_FILE"
            
            echo ""
            echo "────────────────────────────────────────────────────────────"
            echo "Winning Code:"
            echo "────────────────────────────────────────────────────────────"
            cat "$OUTPUT_FILE"
            echo ""
            
            return 0
        fi
        
        round=$((round + 1))
    done
    
    echo ""
    echo "⚠ No winner after $max_rounds rounds"
    return 1
}

# ------------------------------------------------------------
# PHASE 2: Validate and Fix Loop
# ------------------------------------------------------------
phase3_test_and_fix() {
    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "PHASE 2: Validate Winner"
    echo "════════════════════════════════════════════════════════════"

    # First validation
    if run_all_tests; then
        return 0
    fi

    # Validation failed, enter fix loop
    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "PHASE 2b: Fix and Re-validate Loop"
    echo "════════════════════════════════════════════════════════════"

    local attempt=1
    while [[ $attempt -le $MAX_FIX_ATTEMPTS ]]; do
        # Try to fix
        if ! fix_code $attempt; then
            echo "  ✗ Could not generate fix"
            ((attempt++))
            continue
        fi

        # Validate again
        if run_all_tests; then
            echo ""
            echo "  ✓ Code validated after $attempt fix attempt(s)!"
            return 0
        fi

        ((attempt++))
    done

    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "✗ FAILED: Could not fix code after $MAX_FIX_ATTEMPTS attempts"
    echo "════════════════════════════════════════════════════════════"
    return 1
}

# ------------------------------------------------------------
# Main
# ------------------------------------------------------------
main() {
    # Phase 1: Generate and Vote
    if ! phase1_generate_and_vote; then
        echo "Failed in Phase 1"
        exit 1
    fi

    # Phase 2: Validate and Fix (loop until fixed or max attempts)
    if ! phase3_test_and_fix; then
        echo ""
        echo "Final code saved in: $OUTPUT_FILE"
        echo "Check $WORKSPACE_DIR for debug files"
        exit 1
    fi

    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "✓ SUCCESS!"
    echo "════════════════════════════════════════════════════════════"
    echo "  Output: $OUTPUT_FILE"
    echo "  Workspace: $WORKSPACE_DIR"
    echo ""

    exit 0
}

# Run
main
