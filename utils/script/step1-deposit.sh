#!/bin/bash
# Step 1: Deposit ERC20 tokens into TheCompact and obtain tokenId
# This script prepares the solver, deposits user tokens, and extracts the tokenId

# Load shared configuration
SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/config.sh"

# Check requirements
check_requirements

log_info "Step 1: Deposit ERC20 tokens into TheCompact"
log_info "============================================="

# Generate random nonce for this order
NONCE=$((RANDOM % 1001))  # Random nonce between 0-1000
log_info "Generated random nonce for this order: $NONCE"

# Check initial balances
log_info "Checking initial balances..."

USER_ORIGIN_BALANCE=$(cast call $TOKEN_A_ORIGIN "balanceOf(address)" $USER_ADDRESS --rpc-url $ORIGIN_RPC)
USER_DEST_BALANCE=$(cast call $TOKEN_A_DEST "balanceOf(address)" $USER_ADDRESS --rpc-url $DEST_RPC)
SOLVER_DEST_BALANCE=$(cast call $TOKEN_A_DEST "balanceOf(address)" $SOLVER_ADDRESS --rpc-url $DEST_RPC)

log_info "User Origin TokenA balance: $USER_ORIGIN_BALANCE"
log_info "User Destination TokenA balance: $USER_DEST_BALANCE"
log_info "Solver Destination TokenA balance: $SOLVER_DEST_BALANCE"

# Step 1.1: Ensure solver has tokens on destination chain and approval
log_info "Setting up solver on destination chain..."

# Check if solver needs tokens (if balance is less than required amount)
SOLVER_BALANCE_DEC=$(cast to-dec $SOLVER_DEST_BALANCE)
REQUIRED_BALANCE_DEC=$(cast to-dec $SOLVER_TOKEN_AMOUNT)

if [[ $SOLVER_BALANCE_DEC -lt $REQUIRED_BALANCE_DEC ]]; then
    log_info "Solver needs more tokens, transferring..."
    cast send $TOKEN_A_DEST \
        "transfer(address,uint256)" \
        $SOLVER_ADDRESS \
        $SOLVER_TOKEN_AMOUNT \
        --rpc-url $DEST_RPC \
        --private-key $PRIVATE_KEY > /dev/null
    
    log_success "Transferred tokens to solver"
fi

# Approve CoinFiller to spend solver's tokens
log_info "Approving CoinFiller to spend solver's tokens..."
cast send $TOKEN_A_DEST \
    "approve(address,uint256)" \
    $COIN_FILLER \
    $SOLVER_TOKEN_AMOUNT \
    --rpc-url $DEST_RPC \
    --private-key $SOLVER_PRIVATE_KEY > /dev/null

ALLOWANCE=$(cast call $TOKEN_A_DEST "allowance(address,address)" $SOLVER_ADDRESS $COIN_FILLER --rpc-url $DEST_RPC)
log_success "CoinFiller allowance from solver: $ALLOWANCE"

# Step 1.2: Deposit tokens into TheCompact
log_info "Depositing tokens into TheCompact..."

# Approve TokenA for TheCompact
log_info "Approving TokenA for TheCompact..."
cast send $TOKEN_A_ORIGIN \
    "approve(address,uint256)" \
    $THE_COMPACT \
    $DEPOSIT_AMOUNT \
    --rpc-url $ORIGIN_RPC \
    --private-key $PRIVATE_KEY > /dev/null

# Perform the deposit
log_info "Executing deposit transaction..."
DEPOSIT_TX=$(cast send $THE_COMPACT \
    "depositERC20(address,bytes12,uint256,address)" \
    $TOKEN_A_ORIGIN \
    $ALLOCATOR_LOCK_TAG \
    $DEPOSIT_AMOUNT \
    $USER_ADDRESS \
    --rpc-url $ORIGIN_RPC \
    --private-key $PRIVATE_KEY 2>&1)

# Extract token ID from deposit result
TOKEN_ID=""
if echo "$DEPOSIT_TX" | grep -q "Error:"; then
    log_error "Deposit failed: $DEPOSIT_TX"
    
    # Try to calculate expected token ID as fallback
    log_warning "Calculating expected token ID as fallback..."
    LOCK_TAG_CLEAN="${ALLOCATOR_LOCK_TAG#0x}"
    TOKEN_ADDR_CLEAN="${TOKEN_A_ORIGIN#0x}"
    COMBINED_HEX="0x${LOCK_TAG_CLEAN}${TOKEN_ADDR_CLEAN}"
    TOKEN_ID=$(cast to-dec "$COMBINED_HEX" 2>/dev/null || echo "1")
    
    SUCCESS=false
    ERROR_MESSAGE="Deposit transaction failed"
else
    log_success "Deposit transaction completed"
    
    # Extract transaction hash
    TX_HASH=$(echo "$DEPOSIT_TX" | grep -o "0x[a-fA-F0-9]\{64\}" | head -1)
    log_info "Transaction hash: $TX_HASH"
    
    # Calculate token ID based on TheCompact's logic
    # Token ID = (lockTag << 160) | tokenAddress
    LOCK_TAG_CLEAN="${ALLOCATOR_LOCK_TAG#0x}"
    TOKEN_ADDR_CLEAN="${TOKEN_A_ORIGIN#0x}"
    COMBINED_HEX="0x${LOCK_TAG_CLEAN}${TOKEN_ADDR_CLEAN}"
    TOKEN_ID=$(cast to-dec "$COMBINED_HEX" 2>/dev/null || echo "0")
    
    SUCCESS=true
    ERROR_MESSAGE=""
fi

# Verify TheCompact balance
COMPACT_BALANCE=$(cast call $TOKEN_A_ORIGIN "balanceOf(address)" $THE_COMPACT --rpc-url $ORIGIN_RPC)
log_info "TheCompact TokenA balance: $COMPACT_BALANCE"

# Get final balances
FINAL_USER_ORIGIN_BALANCE=$(cast call $TOKEN_A_ORIGIN "balanceOf(address)" $USER_ADDRESS --rpc-url $ORIGIN_RPC)
FINAL_SOLVER_DEST_BALANCE=$(cast call $TOKEN_A_DEST "balanceOf(address)" $SOLVER_ADDRESS --rpc-url $DEST_RPC)

log_success "Step 1 completed"
log_info "Token ID: $TOKEN_ID"

# Create JSON output
RESULT_JSON=$(cat <<EOF
{
  "success": $SUCCESS,
  "step": "deposit",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "tokenId": "$TOKEN_ID",
  "nonce": $NONCE,
  "transactionHash": "${TX_HASH:-null}",
  "deposit": {
    "amount": "$DEPOSIT_AMOUNT",
    "lockTag": "$ALLOCATOR_LOCK_TAG",
    "token": "$TOKEN_A_ORIGIN",
    "user": "$USER_ADDRESS"
  },
  "balances": {
    "userOriginBefore": "$USER_ORIGIN_BALANCE",
    "userOriginAfter": "$FINAL_USER_ORIGIN_BALANCE",
    "theCompactAfter": "$COMPACT_BALANCE",
    "solverDestinationAfter": "$FINAL_SOLVER_DEST_BALANCE"
  },
  "contracts": {
    "theCompact": "$THE_COMPACT",
    "tokenAOrigin": "$TOKEN_A_ORIGIN",
    "coinFiller": "$COIN_FILLER",
    "tokenADestination": "$TOKEN_A_DEST"
  },
  "error": "${ERROR_MESSAGE:-null}"
}
EOF
)

# Save state for next step
echo "$RESULT_JSON" > "$STEP1_STATE_FILE"

# Output JSON result
output_json "$RESULT_JSON" 