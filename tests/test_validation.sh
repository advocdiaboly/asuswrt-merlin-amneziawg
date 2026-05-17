#!/bin/sh
# Unit tests for validation functions in amneziawg.sh

# Mock UINT32_MAX if not sourced
UINT32_MAX=4294967295

# The function to test (copied from addon/amneziawg.sh for unit isolation)
# In the future, we could source the script if we refactor it to be sourceable.
validate_uint() {
    local input="$1"
    local UINT32_MAX=4294967295

    if echo "$input" | grep -qE '^[0-9]+-[0-9]+$'; then
        local lower="${input%-*}"
        local upper="${input#*-}"
        [ "$lower" -le "$upper" ]         || return 1
        [ "$upper" -le "$UINT32_MAX" ]    || return 1
        return 0
    fi

    echo "$input" | grep -qE '^[0-9]+$'  || return 1
    [ "$input" -le "$UINT32_MAX" ]        || return 1
    return 0
}

test_val() {
    local val="$1"
    local expected="$2"
    if validate_uint "$val"; then
        actual="valid"
    else
        actual="invalid"
    fi

    if [ "$actual" = "$expected" ]; then
        echo "PASS: '$val' is $actual"
    else
        echo "FAIL: '$val' expected $expected, got $actual"
        exit 1
    fi
}

echo "Running tests for validate_uint..."

# Single values
test_val "123" "valid"
test_val "0" "valid"
test_val "4294967295" "valid"
test_val "4294967296" "invalid"
test_val "-1" "invalid"
test_val "abc" "invalid"

# Range values
test_val "100-200" "valid"
test_val "200-100" "invalid"
test_val "0-4294967295" "valid"
test_val "0-4294967296" "invalid"
test_val "123-abc" "invalid"
test_val "abc-123" "invalid"
test_val "100-200-300" "invalid"

echo "All tests passed!"
