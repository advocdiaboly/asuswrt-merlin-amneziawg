#!/bin/sh

# Test performance-optimized functions in amneziawg.sh directly.
# This sources the actual script to test the real implementation.

# dummy arg to prevent amneziawg.sh from executing its main block
set -- "test_mode"
. ./addon/amneziawg.sh

TEMP_DIR="/tmp/awg_unit_test"
mkdir -p "$TEMP_DIR/domains"

# --- Mocking ---
log_msg() { :; } # silence logger
get_setting() { :; } # dummy

# --- Test 1: extract_v2fly_domains ---
test_extract_v2fly_domains(){
    echo "Running Test 1: extract_v2fly_domains..."
    
    local input_yml="$TEMP_DIR/v2fly_all.yml"
    cat > "$input_yml" <<EOF
  - name: media
    type: domain
    list:
      - "domain:youtube.com"
      - "full:netflix.com"
  - name: google
    type: domain
    list:
      - "domain:google.com"
EOF

    extract_v2fly_domains "media, google" "$input_yml" "$TEMP_DIR/domains"
    
    if [ ! -s "$TEMP_DIR/domains/v2fly_media.txt" ]; then
        echo "FAIL: v2fly_media.txt empty or missing"
        return 1
    fi
    grep -q "^youtube.com$" "$TEMP_DIR/domains/v2fly_media.txt" || { echo "FAIL: youtube.com missing"; return 1; }
    grep -q "^netflix.com$" "$TEMP_DIR/domains/v2fly_media.txt" || { echo "FAIL: netflix.com missing"; return 1; }
    grep -q "^google.com$" "$TEMP_DIR/domains/v2fly_google.txt" || { echo "FAIL: google.com missing"; return 1; }
    
    echo "PASS: extract_v2fly_domains works"
    return 0
}

# --- Test 2: build_dnsmasq_config ---
test_build_dnsmasq_config(){
    echo "Running Test 2: build_dnsmasq_config..."
    
    # Clean up domains from previous tests
    rm -f "$TEMP_DIR"/domains/*
    
    # Create mock domain files
    echo "site1.com" > "$TEMP_DIR/domains/list1.txt"
    echo "site2.org" >> "$TEMP_DIR/domains/list1.txt"
    echo ".site3.net" > "$TEMP_DIR/domains/list2.txt"
    echo "site4.com:@@ads" >> "$TEMP_DIR/domains/list2.txt"

    local output_conf="$TEMP_DIR/dnsmasq_test.conf"
    local count=$(build_dnsmasq_config "$TEMP_DIR/domains" "$output_conf" "test_ipset")
    
    if [ "$count" -ne 4 ]; then
        echo "FAIL: Expected 4 domains, got $count"
        return 1
    fi
    
    grep -q "ipset=/site1.com/site2.org/test_ipset" "$output_conf" || { echo "FAIL: config line 1 wrong"; return 1; }
    grep -q "ipset=/site3.net/site4.com/test_ipset" "$output_conf" || { echo "FAIL: config cleanup wrong"; return 1; }
    
    echo "PASS: build_dnsmasq_config works"
    return 0
}

# Run tests
test_extract_v2fly_domains || exit 1
test_build_dnsmasq_config || exit 1

# Cleanup
rm -rf "$TEMP_DIR"
echo "ALL UNIT TESTS PASSED"
