#!/bin/bash
# Shared configuration for OIF Protocol workflow scripts

# RPC URLs
export ORIGIN_RPC="http://127.0.0.1:8545"
export DEST_RPC="http://127.0.0.1:8546"

# Private keys and addresses
export PRIVATE_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
export USER_ADDRESS="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"

# Solver configuration
export SOLVER_ADDRESS="0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"
export SOLVER_PRIVATE_KEY="0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a"

# Origin chain contracts
export THE_COMPACT="0x5FbDB2315678afecb367f032d93F642f64180aa3"
export SETTLER_COMPACT="0x5FC8d32690cc91D4c39d9d3abcBD16989F875707"
export TOKEN_A_ORIGIN="0xa513E6E4b8f2a923D98304ec87F64353C4D5C853"
export TOKEN_B_ORIGIN="0x2279B7A0a67DB372996a5FaB50D91eAA73d2eBe6"

# Destination chain contracts
export COIN_FILLER="0x5FbDB2315678afecb367f032d93F642f64180aa3"
export TOKEN_A_DEST="0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0"
export TOKEN_B_DEST="0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9"

# Oracles
export ORIGIN_ORACLE="0x0165878A594ca255338adfa4d48449f69242Eb8F"
export DEST_ORACLE="0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512"

# Chain IDs
export ORIGIN_CHAIN_ID=31337
export DEST_CHAIN_ID=31338

# Amounts
export DEPOSIT_AMOUNT="100000000000000000000"  # 100 tokens
export OUTPUT_AMOUNT="99000000000000000000"   # 99 tokens
export SOLVER_TOKEN_AMOUNT="99000000000000000000"  # 99 tokens for solver

# Allocator lock tag (from Step1_CreateOrder.s.sol)
export ALLOCATOR_LOCK_TAG="0x008367e1bb143e90bb3f0512"

# Order parameters
export EXPIRES=4294967295  # max uint32
export FILL_DEADLINE=4294967295  # max uint32
export NONCE=5  # Default nonce (will be overridden by step1)

# API configuration
export SOLVER_API_URL="http://localhost:3000"

# State files for sharing data between steps
export STATE_DIR="$(dirname "$0")/state"
export STEP1_STATE_FILE="$STATE_DIR/step1-result.json"
export STEP2_STATE_FILE="$STATE_DIR/step2-result.json"
export STEP3_STATE_FILE="$STATE_DIR/step3-result.json"

# Ensure state directory exists
mkdir -p "$STATE_DIR"

# Utility functions
log_info() {
    echo "ℹ️  $1" >&2
}

log_success() {
    echo "✅ $1" >&2
}

log_error() {
    echo "❌ $1" >&2
}

log_warning() {
    echo "⚠️  $1" >&2
}

# JSON output helper
output_json() {
    echo "$1"
}

# Check if required tools are available
check_requirements() {
    if ! command -v cast &> /dev/null; then
        log_error "cast (foundry) is required but not installed"
        exit 1
    fi
    
    if ! command -v curl &> /dev/null; then
        log_error "curl is required but not installed"
        exit 1
    fi
    
    if ! command -v forge &> /dev/null; then
        log_error "forge (foundry) is required but not installed"
        exit 1
    fi
} 