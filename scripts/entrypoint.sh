#!/bin/bash
set -e

echo "=============================================="
echo "  OSRS Hook Discovery Service"
echo "  Schedule: :01 and :31 of each hour"
echo "  Output: /app/data/hooks.json"
echo "=============================================="

# Create directories if needed
mkdir -p /app/data /app/output

# Function to run the gamepack check and deob
run_check() {
    echo ""
    echo "[HOOK-SERVICE] $(date -u +%Y-%m-%dT%H:%M:%SZ) - Checking for gamepack updates..."

    # Step 1: Download gamepack from Jagex
    /app/scripts/download-gamepack.sh

    # Step 2: Check if gamepack changed
    NEW_SHA=$(sha256sum /app/data/gamepack.jar | cut -d' ' -f1)
    OLD_SHA=$(cat /app/data/gamepack.sha256 2>/dev/null || echo "none")

    echo "[HOOK-SERVICE] Current SHA: ${OLD_SHA:0:16}..."
    echo "[HOOK-SERVICE] New SHA:     ${NEW_SHA:0:16}..."

    if [ "$NEW_SHA" != "$OLD_SHA" ]; then
        echo ""
        echo "[HOOK-SERVICE] *** GAMEPACK CHANGED! Running deobfuscation... ***"
        echo ""

        # Step 3: Clean up old deob output (hooks.json stays until replaced)
        echo "[HOOK-SERVICE] Cleaning up old deob output..."
        rm -rf /app/output/*

        # Step 4: Run deobfuscation
        /app/scripts/run-deob.sh

        # Step 5: Convert to hooks.json format
        /app/scripts/convert-hooks.sh

        # Step 6: Save new SHA
        echo "$NEW_SHA" > /app/data/gamepack.sha256

        echo ""
        echo "[HOOK-SERVICE] *** UPDATE COMPLETE! ***"
        echo "[HOOK-SERVICE] hooks.json available at: /app/data/hooks.json"
        echo ""
    else
        echo "[HOOK-SERVICE] No changes detected."
    fi
}

# Function to wait until :01 or :31 of the hour
wait_for_schedule() {
    while true; do
        MINUTE=$(date +%M)
        SECOND=$(date +%S)

        # Target: 01 or 31 minutes (1 minute after Jagex's :00/:30)
        if [ "$MINUTE" = "01" ] || [ "$MINUTE" = "31" ]; then
            # We're in the target minute, break out
            break
        fi

        # Calculate seconds until next target
        if [ "$MINUTE" -lt "01" ]; then
            # Wait until :01
            WAIT_MIN=$((1 - MINUTE))
        elif [ "$MINUTE" -lt "31" ]; then
            # Wait until :31
            WAIT_MIN=$((31 - MINUTE))
        else
            # Wait until next hour's :01
            WAIT_MIN=$((61 - MINUTE))
        fi

        WAIT_SEC=$((WAIT_MIN * 60 - SECOND))
        echo "[HOOK-SERVICE] Waiting ${WAIT_SEC}s until next check ($(date -u -d "+${WAIT_SEC} seconds" +%H:%M:%S) UTC)..."
        sleep $WAIT_SEC
    done
}

# === FIRST RUN: Always run immediately on startup ===
echo ""
echo "[HOOK-SERVICE] *** INITIAL STARTUP - Running first check immediately ***"
run_check

# === SCHEDULED LOOP: Wait for :01/:31 after first run ===
while true; do
    # Sleep 60 seconds to avoid re-running in same minute as first run
    sleep 60

    # Wait for scheduled time (:01 or :31)
    wait_for_schedule

    # Run the check
    run_check

    # Sleep 60 seconds to avoid re-running in same minute
    sleep 60
done
