# OIF Protocol Solver - System Overview & Demo

## 🎯 **System Overview**

The **OIF-Solver** is a TypeScript-based REST API that orchestrates cross-chain intent execution:

### **Key Features**
- **🌐 REST API**: TypeScript-based server with comprehensive endpoints
- **⛓️ Multi-Chain Support**: Configurable source and destination chains
- **📄 Order Support**: Implements StandardOrder specification
- **🛡️ Robust Architecture**: 
  - Proper error handling & retry logic
  - Real-time status tracking
  - Event-driven processing
- **💾 Storage**: In-memory order management with state persistence
- **🔄 Automated Execution**: Background processing of cross-chain operations

### **Architecture Components**
```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Origin Chain  │    │  OIF-Solver API │    │ Destination Chain│
│   (TheCompact)  │◄──►│  (Orchestrator) │◄──►│  (CoinFiller)   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

---

## 🎭 **Demo Workflow**

### **Step 1: Token Deposit & Setup** 🏦
**Location**: Origin Chain (ON-CHAIN)  
**Action**: User deposits ERC20 tokens and obtains tokenId

**What happens:**
- User approves TokenA for TheCompact contract
- User calls `depositERC20(token, lockTag, amount, user)`
- TheCompact mints a unique `tokenId` representing the deposit
- Tokens are locked in TheCompact vault

**Result**: User receives a `tokenId` that represents their cross-chain intent collateral

---

### **Step 2: Intent Submission & Fill** 📝⚡
**Location**: Off-chain → Destination Chain  
**Action**: Create user intent signature and submit to solver

**What happens:**
- **Off-chain**: User generates EIP-712 signature for their intent
- **API Call**: `POST /api/v1/orders` - Submit signed order to solver
- **Auto-Fill**: Solver immediately executes fill on destination chain
- **Destination Chain**: CoinFiller contract transfers tokens to user

**Key Features:**
- Single signature from user (EIP-712 standard)
- Automatic cross-chain execution
- Real-time status tracking
- No manual intervention required

**Result**: User receives tokens on destination chain, order status becomes `filled`

---

### **Step 3: Finalization & Settlement** 🏁
**Location**: Origin Chain (ON-CHAIN)  
**Action**: Finalize order and release tokens to solver

**What happens:**
- **API Call**: `POST /api/v1/orders/:orderId/finalize`
- **Origin Chain**: SettlerCompact.finalise() verifies signature and execution
- **Token Release**: TheCompact releases locked tokens to solver
- **Settlement**: Cross-chain transaction completed

**Result**: Solver receives compensation, user's cross-chain intent fulfilled

---

## 🔧 **Technical Implementation**

### **API Endpoints**
```typescript
GET    /api/v1/health           // System health check
POST   /api/v1/orders           // Submit new order
GET    /api/v1/orders/:id       // Check order status  
POST   /api/v1/orders/:id/finalize // Manual finalization
GET    /api/v1/queue            // View processing queue
```

### **Order Lifecycle**
```
pending → processing → filled → finalized
                    ↘  failed
```

### **Error Handling**
- Retry logic for failed transactions
- Comprehensive error reporting
- Graceful degradation
- Status persistence across restarts

---

## 🚀 **Demo Script Commands**

```bash
# Step 1: Deposit tokens (get tokenId)
./scripts/step1-deposit.sh

# Step 2: Submit order (automatic fill)
./scripts/step2-submit-order.sh  

# Step 3: Finalize order (complete settlement)
./scripts/step3-finalize.sh

# Monitor progress
curl http://localhost:3000/api/v1/queue
```

---

## ✨ **Key Benefits**

- **🎯 Intent-Based**: Users express what they want, not how to do it
- **🔄 Automated**: No manual cross-chain coordination required
- **🛡️ Secure**: Signature verification and atomic settlement
- **📊 Transparent**: Full visibility into order status and execution
- **🌐 Extensible**: Easy to add new chains and token pairs

---

## 🔍 **What Makes This Special**

1. **Single Signature**: User signs once, solver handles everything
2. **Atomic Settlement**: Either complete success or safe failure
3. **Real-time Monitoring**: Track orders through entire lifecycle
4. **Developer Friendly**: Simple REST API vs complex multi-chain setup
5. **Production Ready**: Proper error handling, logging, and monitoring
