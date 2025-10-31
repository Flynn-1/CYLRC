# 🪙 CYLRC — CYLRC Smart Contract

### Overview
**CYLRC (CYLRC)** is a secure and feature-rich ERC20 token built with OpenZeppelin, combining traditional tokenomics with flexible administrative control and an integrated reward mechanism.

---

### 🚀 Key Features
- 🏦 **Fixed Max Supply:** 200,000,000 CYLRC (6 decimals)
- 💰 **Reward Pool:** 25% reserved for daily claimable rewards
- 🔁 **Dual APY Modes:**
  - Inflation-based APY (auto-adjusts to token inflation)
  - Manual APY (admin-controlled)
- 🔥 **Burn Mechanisms:**
  - Scheduled yearly burn (0.001%)
  - User deposit burn system
  - Manual admin burns
- 🎁 **Airdrop System:** Role-based with 50-address batch limit
- 🔐 **Access Control:** Separate roles for admin, burn, and airdrop
- ♻️ **Recovery:** Safely recover ERC20 or ETH sent by mistake
- ⚙️ **Permit Support (EIP-2612):** Gasless approvals

---

### 🧩 Roles
| Role | Permission |
|------|-------------|
| `ADMIN_ROLE` | Full administrative control |
| `AIRDROP_ROLE` | Send batch airdrops |
| `BURN_ROLE` | Trigger token burns |

---

### 🧱 Technical Stack
- Solidity ^0.8.20  
- OpenZeppelin Contracts  
- ERC20 + ERC20Permit  
- AccessControl for modular permissions  
- SafeERC20 for secure transfers  

---

### 📈 Tokenomics
- **Max Supply:** 200,000,000 CYLRC  
- **Initial Mint:** 75% (to Circulation)  
- **Reward Pool:** 15% (for holders)
- **Pre AirDrop:** 10% (for Early investor)
- **Decimals:** 6  

---

### 🛠️ Contract Functions
- `mint()`, `airdrop()`, `depositForBurn()`, `claimReward()`
- `activateManualAPY()`, `activateInflationAPY()`
- `recoverERC20()`, `transferAdmin()`
- `increaseAllowance()`, `decreaseAllowance()`

---

<img width="1536" height="1024" alt="Diagram" src="https://github.com/user-attachments/assets/89d27eb5-87e6-498b-ab59-99590afbfad2" />





### 🧾 License
Licensed under the **MIT License**.  
Developed by **Flynn Corps** — any future changes will be publicly announced.
