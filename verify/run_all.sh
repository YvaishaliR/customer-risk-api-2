#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SCRIPTS=(
    "verify/s2_db.sh"
    "verify/s3_auth.sh"
    "verify/s4_api.sh"
    "verify/s5_nginx.sh"
    "verify/s5_isolation.sh"
    "verify/s6_ui.sh"
    "verify/s7_coldstart.sh"
    "verify/s7_invariants_data.sh"
    "verify/s7_invariants_auth.sh"
    "verify/s7_invariants_schema.sh"
)

RESULTS=()
OVERALL=0

cd "$PROJECT_ROOT"

for SCRIPT in "${SCRIPTS[@]}"; do
    echo ""
    echo "================================================================"
    echo "Running: $SCRIPT"
    echo "================================================================"
    if bash "$SCRIPT"; then
        RESULTS+=("PASS")
    else
        RESULTS+=("FAIL")
        OVERALL=1
    fi
done

echo ""
echo "================================================================"
echo "Summary"
echo "================================================================"
printf "%-34s | %s\n" "Script" "Result"
printf "%-34s-+-%s\n" "----------------------------------" "------"
for i in "${!SCRIPTS[@]}"; do
    printf "%-34s | %s\n" "${SCRIPTS[$i]}" "${RESULTS[$i]}"
done

echo ""
if [ "$OVERALL" -eq 0 ]; then
    echo "Overall: PASS"
    exit 0
else
    echo "Overall: FAIL"
    echo ""
    echo "Failed scripts:"
    for i in "${!SCRIPTS[@]}"; do
        if [ "${RESULTS[$i]}" = "FAIL" ]; then
            echo "  ${SCRIPTS[$i]}"
        fi
    done
    exit 1
fi
