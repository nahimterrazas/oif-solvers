#!/bin/bash
# Step 3: Finalize order on origin chain
# This script calls the finalize endpoint to complete the order

# Load shared configuration
SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/config.sh"

# Check requirements
check_requirements

log_info "Step 3: Finalize order on origin chain"
log_info "======================================="

# Check if step2 completed successfully
if [[ ! -f "$STEP2_STATE_FILE" ]]; then
    log_error "Step 2 must be completed first. Run step2-submit-order.sh"
    
    ERROR_JSON=$(cat <<EOF
{
  "success": false,
  "step": "finalize",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "error": "Step 2 not completed. Missing state file: $STEP2_STATE_FILE"
}
EOF
)
    output_json "$ERROR_JSON"
    exit 1
fi

# Load step2 results
STEP2_RESULT=$(cat "$STEP2_STATE_FILE")

# More robust JSON parsing for boolean values
if command -v jq &> /dev/null; then
    # Use jq if available (most reliable)
    STEP2_SUCCESS=$(echo "$STEP2_RESULT" | jq -r '.success')
    ORDER_ID=$(echo "$STEP2_RESULT" | jq -r '.orderId')
    NONCE=$(echo "$STEP2_RESULT" | jq -r '.order.nonce')
else
    # Fallback parsing for boolean true/false
    if echo "$STEP2_RESULT" | grep -q '"success"[[:space:]]*:[[:space:]]*true'; then
        STEP2_SUCCESS="true"
    else
        STEP2_SUCCESS="false"
    fi
    ORDER_ID=$(echo "$STEP2_RESULT" | grep -o '"orderId":"[^"]*"' | cut -d':' -f2 | tr -d '"')
    NONCE=$(echo "$STEP2_RESULT" | grep -o '"nonce":[^,}]*' | cut -d':' -f2 | tr -d ' ')
fi

# Debug output
log_info "Extracted STEP2_SUCCESS: '$STEP2_SUCCESS'"
log_info "Extracted ORDER_ID: '$ORDER_ID'"
log_info "Extracted NONCE: '$NONCE'"

if [[ "$STEP2_SUCCESS" != "true" ]]; then
    log_error "Step 2 did not complete successfully"
    
    ERROR_JSON=$(cat <<EOF
{
  "success": false,
  "step": "finalize",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "error": "Step 2 failed. Check step2 results."
}
EOF
)
    output_json "$ERROR_JSON"
    exit 1
fi

if [[ -z "$ORDER_ID" || "$ORDER_ID" == "null" ]]; then
    log_error "No valid order ID found from step 2"
    
    ERROR_JSON=$(cat <<EOF
{
  "success": false,
  "step": "finalize",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "error": "No valid order ID from step 2"
}
EOF
)
    output_json "$ERROR_JSON"
    exit 1
fi

log_info "Loaded order ID from step 2: $ORDER_ID"

# Step 3.1: Check order status before finalization
log_info "Checking order status before finalization..."

ORDER_STATUS_RESPONSE=$(curl -s "$SOLVER_API_URL/api/v1/orders/$ORDER_ID" 2>&1)
log_info "Current order status: $ORDER_STATUS_RESPONSE"

# Parse order status
CURRENT_STATUS=$(echo "$ORDER_STATUS_RESPONSE" | grep -o '"status":"[^"]*"' | cut -d':' -f2 | tr -d '"')
log_info "Order status: $CURRENT_STATUS"

# Step 3.2: Wait for order to be filled (if needed)
if [[ "$CURRENT_STATUS" == "processing" || "$CURRENT_STATUS" == "pending" ]]; then
    log_info "Order is still processing, waiting for fill to complete..."
    
    # Wait up to 60 seconds for the order to be filled
    WAIT_COUNT=0
    MAX_WAIT=60
    
    while [[ $WAIT_COUNT -lt $MAX_WAIT && "$CURRENT_STATUS" != "filled" && "$CURRENT_STATUS" != "failed" ]]; do
        sleep 2
        WAIT_COUNT=$((WAIT_COUNT + 2))
        
        ORDER_STATUS_RESPONSE=$(curl -s "$SOLVER_API_URL/api/v1/orders/$ORDER_ID" 2>&1)
        CURRENT_STATUS=$(echo "$ORDER_STATUS_RESPONSE" | grep -o '"status":"[^"]*"' | cut -d':' -f2 | tr -d '"')
        
        log_info "Waiting... Current status: $CURRENT_STATUS (${WAIT_COUNT}s)"
    done
    
    if [[ "$CURRENT_STATUS" == "failed" ]]; then
        log_error "Order failed during fill process"
        
        ERROR_JSON=$(cat <<EOF
{
  "success": false,
  "step": "finalize",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "orderId": "$ORDER_ID",
  "error": "Order failed during fill process",
  "orderStatus": $ORDER_STATUS_RESPONSE
}
EOF
)
        output_json "$ERROR_JSON"
        exit 1
    fi
    
    if [[ "$CURRENT_STATUS" != "filled" ]]; then
        log_warning "Order has not been filled yet after ${MAX_WAIT}s wait"
        log_info "Current status: $CURRENT_STATUS"
        log_info "Proceeding with finalization attempt anyway..."
    fi
fi

# Step 3.3: Get initial balances
log_info "Getting initial balances..."

INITIAL_USER_ORIGIN_BALANCE=$(cast call $TOKEN_A_ORIGIN "balanceOf(address)" $USER_ADDRESS --rpc-url $ORIGIN_RPC)
INITIAL_USER_DEST_BALANCE=$(cast call $TOKEN_A_DEST "balanceOf(address)" $USER_ADDRESS --rpc-url $DEST_RPC)
INITIAL_SOLVER_DEST_BALANCE=$(cast call $TOKEN_A_DEST "balanceOf(address)" $SOLVER_ADDRESS --rpc-url $DEST_RPC)
INITIAL_COMPACT_BALANCE=$(cast call $TOKEN_A_ORIGIN "balanceOf(address)" $THE_COMPACT --rpc-url $ORIGIN_RPC)

log_info "Initial balances:"
log_info "  User Origin TokenA: $INITIAL_USER_ORIGIN_BALANCE"
log_info "  User Dest TokenA: $INITIAL_USER_DEST_BALANCE"
log_info "  Solver Dest TokenA: $INITIAL_SOLVER_DEST_BALANCE"
log_info "  TheCompact TokenA: $INITIAL_COMPACT_BALANCE"

# Step 3.4: Call finalize endpoint
log_info "Calling finalize endpoint..."

FINALIZE_RESPONSE=$(curl -s -X POST "$SOLVER_API_URL/api/v1/orders/$ORDER_ID/finalize" \
    -H "Content-Type: application/json" 2>&1)

log_info "Finalize API response: $FINALIZE_RESPONSE"

# Parse finalize response
if echo "$FINALIZE_RESPONSE" | grep -q '"success":true'; then
    log_success "Order finalized successfully"
    
    FINALIZED_AT=$(echo "$FINALIZE_RESPONSE" | grep -o '"finalizedAt":"[^"]*"' | cut -d':' -f2- | tr -d '"')
    
    SUCCESS=true
    ERROR_MESSAGE=""
else
    log_error "Failed to finalize order"
    
    # Extract error message if available
    ERROR_FROM_API=$(echo "$FINALIZE_RESPONSE" | grep -o '"message":"[^"]*"' | cut -d':' -f2- | tr -d '"')
    if [[ -z "$ERROR_FROM_API" ]]; then
        ERROR_FROM_API=$(echo "$FINALIZE_RESPONSE" | grep -o '"error":"[^"]*"' | cut -d':' -f2- | tr -d '"')
    fi
    
    SUCCESS=false
    ERROR_MESSAGE="Finalization failed: ${ERROR_FROM_API:-Unknown error}"
    FINALIZED_AT=""
fi

# Step 3.5: Get final balances
log_info "Getting final balances..."

FINAL_USER_ORIGIN_BALANCE=$(cast call $TOKEN_A_ORIGIN "balanceOf(address)" $USER_ADDRESS --rpc-url $ORIGIN_RPC)
FINAL_USER_DEST_BALANCE=$(cast call $TOKEN_A_DEST "balanceOf(address)" $USER_ADDRESS --rpc-url $DEST_RPC)
FINAL_SOLVER_DEST_BALANCE=$(cast call $TOKEN_A_DEST "balanceOf(address)" $SOLVER_ADDRESS --rpc-url $DEST_RPC)
FINAL_COMPACT_BALANCE=$(cast call $TOKEN_A_ORIGIN "balanceOf(address)" $THE_COMPACT --rpc-url $ORIGIN_RPC)

log_info "Final balances:"
log_info "  User Origin TokenA: $FINAL_USER_ORIGIN_BALANCE"
log_info "  User Dest TokenA: $FINAL_USER_DEST_BALANCE"
log_info "  Solver Dest TokenA: $FINAL_SOLVER_DEST_BALANCE"
log_info "  TheCompact TokenA: $FINAL_COMPACT_BALANCE"

# Step 3.6: Get final order status
FINAL_ORDER_STATUS_RESPONSE=$(curl -s "$SOLVER_API_URL/api/v1/orders/$ORDER_ID" 2>&1)
FINAL_STATUS=$(echo "$FINAL_ORDER_STATUS_RESPONSE" | grep -o '"status":"[^"]*"' | cut -d':' -f2 | tr -d '"')

# Step 3.7: Get final queue status
FINAL_QUEUE_RESPONSE=$(curl -s "$SOLVER_API_URL/api/v1/queue" 2>&1)

log_success "Step 3 completed"
log_info "Final order status: $FINAL_STATUS"

# Calculate balance changes
USER_ORIGIN_CHANGE=$(echo "$FINAL_USER_ORIGIN_BALANCE - $INITIAL_USER_ORIGIN_BALANCE" | bc 2>/dev/null || echo "N/A")
USER_DEST_CHANGE=$(echo "$FINAL_USER_DEST_BALANCE - $INITIAL_USER_DEST_BALANCE" | bc 2>/dev/null || echo "N/A")
SOLVER_DEST_CHANGE=$(echo "$FINAL_SOLVER_DEST_BALANCE - $INITIAL_SOLVER_DEST_BALANCE" | bc 2>/dev/null || echo "N/A")
COMPACT_CHANGE=$(echo "$FINAL_COMPACT_BALANCE - $INITIAL_COMPACT_BALANCE" | bc 2>/dev/null || echo "N/A")

# Create JSON output
RESULT_JSON=$(cat <<EOF
{
  "success": $SUCCESS,
  "step": "finalize",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "orderId": "$ORDER_ID",
  "finalizedAt": "${FINALIZED_AT:-null}",
  "finalStatus": "$FINAL_STATUS",
  "balances": {
    "initial": {
      "userOrigin": "$INITIAL_USER_ORIGIN_BALANCE",
      "userDestination": "$INITIAL_USER_DEST_BALANCE",
      "solverDestination": "$INITIAL_SOLVER_DEST_BALANCE",
      "theCompact": "$INITIAL_COMPACT_BALANCE"
    },
    "final": {
      "userOrigin": "$FINAL_USER_ORIGIN_BALANCE",
      "userDestination": "$FINAL_USER_DEST_BALANCE",
      "solverDestination": "$FINAL_SOLVER_DEST_BALANCE",
      "theCompact": "$FINAL_COMPACT_BALANCE"
    },
    "changes": {
      "userOrigin": "$USER_ORIGIN_CHANGE",
      "userDestination": "$USER_DEST_CHANGE",
      "solverDestination": "$SOLVER_DEST_CHANGE",
      "theCompact": "$COMPACT_CHANGE"
    }
  },
  "finalizeResponse": $FINALIZE_RESPONSE,
  "finalOrderStatus": $FINAL_ORDER_STATUS_RESPONSE,
  "finalQueueStatus": $FINAL_QUEUE_RESPONSE,
  "error": "${ERROR_MESSAGE:-null}"
}
EOF
)

# Save state
echo "$RESULT_JSON" > "$STEP3_STATE_FILE"

# Output JSON result
output_json "$RESULT_JSON" 