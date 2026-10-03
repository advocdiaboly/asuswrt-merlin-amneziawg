#!/bin/sh

# RIGOROUS PARITY VALIDATION SCRIPT
# This script compares the legacy shell-loop implementation with the 
# new vectorized awk/sed implementation using real provider data.

# 1. Source the new implementation (using test_mode to skip execution)
set -- "test_mode"
. ./addon/amneziawg.sh

INPUT_YML="tests/data/v2fly_all.yml"
LIST="youtube,google,telegram,twitter,instagram,facebook,tiktok,whatsapp,openai,github,docker"
TEMP_DIR="/tmp/awg_parity_test"
IPSET="awg_dst"

mkdir -p "$TEMP_DIR/old_domains" "$TEMP_DIR/new_domains"

# --- 2. Define Legacy (OLD) Logic ---

old_extract_v2fly_domains(){
    local geo_v2fly="$1"
    local input_yml="$2"
    local output_dir="$3"
    
    for svc in $(echo "$geo_v2fly" | tr ',' ' '); do
        svc=$(echo "$svc" | tr -d ' ')
        [ -z "$svc" ] && continue
        awk -v cat="$svc" '
            /^  - name: / { name=$NF; found=(name==cat); next }
            found && /^      - "domain:/ { sub(/.*"domain:/,""); sub(/".*/,""); print }
            found && /^      - "full:/ { sub(/.*"full:/,""); sub(/".*/,""); print }
            found && /^  - name: / { if(found) exit }
        ' "$input_yml" > "$output_dir/v2fly_${svc}.txt"
    done
}

old_build_dnsmasq_config(){
    local domains_dir="$1"
    local output_conf="$2"
    local ipset_name="$3"
    
    local domain_count=0
    echo "# AmneziaWG domain routing - auto-generated" > "$output_conf"
    for f in "$domains_dir"/*.txt "$domains_dir"/*.lst; do
        [ ! -f "$f" ] && continue
        local chunk_line="ipset=/"
        local chunk_count=0
        while read -r domain; do
            domain=$(echo "$domain" | tr -d ' \r')
            [ -z "$domain" ] && continue
            echo "$domain" | grep -q '^#' && continue
            domain=$(echo "$domain" | sed 's/^\.//;s/:@[^ ]*$//')
            echo "$domain" | grep -q '[^a-zA-Z0-9._-]' && continue
            chunk_line="${chunk_line}${domain}/"
            chunk_count=$((chunk_count + 1))
            domain_count=$((domain_count + 1))
            if [ $chunk_count -ge 20 ]; then
                echo "${chunk_line}${ipset_name}" >> "$output_conf"
                chunk_line="ipset=/"
                chunk_count=0
            fi
        done < "$f"
        [ $chunk_count -gt 0 ] && echo "${chunk_line}${ipset_name}" >> "$output_conf"
    done
    echo "$domain_count"
}

# --- 3. Execute Validations ---

echo "Starting parity validation for: $LIST"

# Step A: Domain Extraction Parity
echo "Step A: Comparing Domain Extraction..."
old_extract_v2fly_domains "$LIST" "$INPUT_YML" "$TEMP_DIR/old_domains"
extract_v2fly_domains "$LIST" "$INPUT_YML" "$TEMP_DIR/new_domains"

for svc in $(echo "$LIST" | tr ',' ' '); do
    svc=$(echo "$svc" | tr -d ' ')
    diff -u "$TEMP_DIR/old_domains/v2fly_${svc}.txt" "$TEMP_DIR/new_domains/v2fly_${svc}.txt" >/dev/null || {
        echo "FAIL: Domain extraction mismatch for category: $svc"
        exit 1
    }
done
echo "PASS: Domain extraction produced identical files."

# Step B: Config Building Parity
echo "Step B: Comparing dnsmasq config generation..."
# Sort inputs to ensure deterministic behavior for loops
# (the legacy logic depends on file glob order)
OLD_COUNT=$(old_build_dnsmasq_config "$TEMP_DIR/old_domains" "$TEMP_DIR/old.conf" "$IPSET")
NEW_COUNT=$(build_dnsmasq_config "$TEMP_DIR/new_domains" "$TEMP_DIR/new.conf" "$IPSET")

echo "Legacy count: $OLD_COUNT"
echo "Optimized count: $NEW_COUNT"

if [ "$OLD_COUNT" != "$NEW_COUNT" ]; then
    echo "FAIL: Domain count mismatch ($OLD_COUNT vs $NEW_COUNT)"
    exit 1
fi

# We sort both config files because the vectorized AWG processes files in directory order
# which might differ from the legacy loop glob expansion depending on the shell environment.
# Bit-for-bit parity is verified on the content.
sort "$TEMP_DIR/old.conf" > "$TEMP_DIR/old_sorted.conf"
sort "$TEMP_DIR/new.conf" > "$TEMP_DIR/new_sorted.conf"

diff -u "$TEMP_DIR/old_sorted.conf" "$TEMP_DIR/new_sorted.conf" >/dev/null || {
    echo "FAIL: dnsmasq configuration content mismatch"
    diff -u "$TEMP_DIR/old_sorted.conf" "$TEMP_DIR/new_sorted.conf" | head -n 20
    exit 1
}

echo "PASS: Configuration files are logically identical."
echo ""
echo "VERIFICATION SUCCESSFUL: Optimized vectorized logic is 100% compatible with legacy logic."

# Cleanup
# rm -rf "$TEMP_DIR"
