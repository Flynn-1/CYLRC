// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title TXTON - trimmed for size (optimized strings/events)
 */
contract TXTON is ERC20, ERC20Permit, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint8 public constant DECIMALS = 6;
    uint256 public constant MAX_SUPPLY = 200_000_000 * (10 ** DECIMALS);
    uint256 public constant MAX_AIRDROP_BATCH = 50;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant AIRDROP_ROLE = keccak256("AIRDROP_ROLE");
    bytes32 public constant BURN_ROLE = keccak256("BURN_ROLE");
    bytes32 public constant MINT_ROLE = keccak256("MINT_ROLE");

    uint64 public lastBurnTimestamp;
    uint64 public burnInterval = uint64(365 days);
    address public admin;

    // Rewards & deposits
    uint256 public rewardPool;
    uint256 public depositBalance;
    bool public rewardsActive = true;
    mapping(address => uint256) public lastClaimed;

    // APY vars: bps where 10000 = 100%
    uint128 public rewardAPYBps = 50; // 0.5%
    uint128 public pendingRewardAPY;
    uint256 public pendingRewardAPYTimestamp;
    uint256 public apyChangeDelay = 2 days;

    bool public burnPaused;

    // --- Events (kept essential ones) ---
    event Burned(uint256 amount, uint256 timestamp);
    event Minted(address indexed to, uint256 amount);
    event DepositForBurn(address indexed user, uint256 amount);
    event Airdropped(address indexed to, uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);
    event RewardsToggled(bool active);
    event RewardPoolRefilled(uint256 needed, uint256 minted, uint256 reclaimed);
    event ETHWithdrawn(address indexed to, uint256 amount);
    event ClaimInitialized(address indexed user, uint256 timestamp);
    event AdminTransferred(address indexed oldAdmin, address indexed newAdmin);

    event RewardAPYProposed(uint128 newAPY, uint256 effectiveTimestamp, address proposer);
    event RewardAPYApplied(uint128 oldAPY, uint128 newAPY, address applier);
    event RewardAPYCancelled(uint128 cancelledAPY, address canceller);
    event RewardAPYChangeDelayUpdated(uint256 oldDelay, uint256 newDelay);
    event BurnPaused(bool paused);

    constructor() ERC20("TX Token", "TXTON") ERC20Permit("TX Token") {
        admin = msg.sender;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(MINT_ROLE, admin);

        uint256 adminMint = (MAX_SUPPLY * 25) / 100;
        _mint(admin, adminMint);
        emit Minted(admin, adminMint);

        lastBurnTimestamp = uint64(block.timestamp);
    }

    // --- Views ---
    function decimals() public pure override returns (uint8) {
        return DECIMALS;
    }

    function depositedBalance() external view returns (uint256) {
        return depositBalance;
    }

    function contractBalance() external view returns (uint256) {
        return balanceOf(address(this));
    }

    function nextBurnTime() external view returns (uint256) {
        return uint256(lastBurnTimestamp) + uint256(burnInterval);
    }

    function mintableSupply() public view returns (uint256) {
        return MAX_SUPPLY - totalSupply();
    }

    function pendingAPYInfo() external view returns (uint128 apyBps, uint256 effectiveTimestamp) {
        apyBps = pendingRewardAPY;
        effectiveTimestamp = pendingRewardAPYTimestamp;
    }

    // --- Admin config ---
    function updateBurnConfig(uint64 newInterval) external onlyRole(ADMIN_ROLE) {
        require(newInterval >= 1 days);
        burnInterval = newInterval;
        emit BurnPaused(burnPaused); // minimal emitted signal for config change
    }

    function setAPYChangeDelay(uint256 newDelay) external onlyRole(ADMIN_ROLE) {
        require(newDelay >= 1 hours && newDelay <= 30 days);
        uint256 old = apyChangeDelay;
        apyChangeDelay = newDelay;
        emit RewardAPYChangeDelayUpdated(old, newDelay);
    }

    function proposeRewardAPY(uint128 newAPY) external onlyRole(ADMIN_ROLE) {
        require(newAPY <= 10000);
        require(newAPY != rewardAPYBps);
        pendingRewardAPY = newAPY;
        pendingRewardAPYTimestamp = block.timestamp + apyChangeDelay;
        emit RewardAPYProposed(newAPY, pendingRewardAPYTimestamp, msg.sender);
    }

    function applyPendingRewardAPY() external onlyRole(ADMIN_ROLE) {
        require(pendingRewardAPY != 0);
        require(block.timestamp >= pendingRewardAPYTimestamp);
        uint128 old = rewardAPYBps;
        uint128 neu = pendingRewardAPY;
        pendingRewardAPY = 0;
        pendingRewardAPYTimestamp = 0;
        rewardAPYBps = neu;
        emit RewardAPYApplied(old, neu, msg.sender);
    }

    function cancelPendingRewardAPY() external onlyRole(ADMIN_ROLE) {
        require(pendingRewardAPY != 0);
        uint128 cancelled = pendingRewardAPY;
        pendingRewardAPY = 0;
        pendingRewardAPYTimestamp = 0;
        emit RewardAPYCancelled(cancelled, msg.sender);
    }

    // --- Minting ---
    function mint(address to, uint256 amount) external onlyRole(MINT_ROLE) nonReentrant {
        require(to != address(0));
        require(amount > 0);
        require(totalSupply() + amount <= MAX_SUPPLY);
        _mint(to, amount);
        if (to == address(this)) rewardPool += amount;
        emit Minted(to, amount);
    }

    // --- Deposit & Burn ---
    function depositForBurn(uint256 amount) external nonReentrant {
        require(amount > 0);
        _transfer(msg.sender, address(this), amount);
        depositBalance += amount;
        emit DepositForBurn(msg.sender, amount);
    }

    function adminBurn(uint256 amount) external onlyRole(ADMIN_ROLE) nonReentrant {
        require(amount > 0);
        _burn(msg.sender, amount);
        emit Burned(amount, block.timestamp);
    }

    function triggerBurnFromDeposits() external onlyRole(BURN_ROLE) nonReentrant {
        require(!burnPaused);
        require(block.timestamp >= lastBurnTimestamp + burnInterval);

        uint256 burnAmt = totalSupply() / 100_000; // 0.001%
        if (burnAmt == 0) burnAmt = 1 * (10 ** DECIMALS);

        uint256 bal = balanceOf(address(this));
        require(bal >= burnAmt);

        uint256 burnFromDeposits = burnAmt <= depositBalance ? burnAmt : depositBalance;
        uint256 remaining = burnAmt - burnFromDeposits;

        if (burnFromDeposits > 0) depositBalance -= burnFromDeposits;

        if (remaining > 0) {
            if (rewardPool >= remaining) rewardPool -= remaining;
            else {
                remaining = rewardPool;
                rewardPool = 0;
            }
        }

        _burn(address(this), burnAmt);
        lastBurnTimestamp = uint64(block.timestamp);
        emit Burned(burnAmt, block.timestamp);
    }

    function burnAllDeposited() external onlyRole(BURN_ROLE) nonReentrant {
        require(!burnPaused);
        uint256 bal = depositBalance;
        require(bal > 0);
        depositBalance = 0;
        _burn(address(this), bal);
        emit Burned(bal, block.timestamp);
    }

    // --- Airdrop ---
    function airdrop(address[] calldata recipients, uint256[] calldata amounts)
        external
        onlyRole(AIRDROP_ROLE)
        nonReentrant
    {
        uint256 len = recipients.length;
        require(len == amounts.length);
        require(len <= MAX_AIRDROP_BATCH);

        for (uint256 i = 0; i < len; i++) {
            uint256 amt = amounts[i];
            require(amt > 0);
            require(totalSupply() + amt <= MAX_SUPPLY);
            _mint(recipients[i], amt);
            emit Airdropped(recipients[i], amt);
        }
    }

    // --- ERC20 recovery ---
  function recoverToken(address token, address to, uint256 amount)
    external
    onlyRole(ADMIN_ROLE)
    nonReentrant
{
    require(to != address(0), "Invalid recipient");
    require(amount > 0, "Invalid amount");

    if (token == address(this)) {
        // Recover TXTON safely — only excess tokens not used for rewards or burns
        uint256 contractBal = balanceOf(address(this));
        uint256 reserved = rewardPool + depositBalance;
        require(contractBal > reserved, "No excess TXTON to recover");

        uint256 available = contractBal - reserved;
        require(amount <= available, "Amount exceeds recoverable TXTON");

        _transfer(address(this), to, amount);
    } else {
        // Recover any other ERC20 token safely
        IERC20(token).safeTransfer(to, amount);
    }
}



    // --- Admin transfer ---
    function transferAdmin(address newAdmin) external onlyRole(ADMIN_ROLE) nonReentrant {
        require(newAdmin != address(0));
        address oldAdmin = admin;
        _grantRole(DEFAULT_ADMIN_ROLE, newAdmin);
        _grantRole(ADMIN_ROLE, newAdmin);
        _grantRole(MINT_ROLE, newAdmin);
        _revokeRole(ADMIN_ROLE, oldAdmin);
        _revokeRole(DEFAULT_ADMIN_ROLE, oldAdmin);
        _revokeRole(MINT_ROLE, oldAdmin);
        admin = newAdmin;
        emit AdminTransferred(oldAdmin, newAdmin);
    }

    function renounceAdminRole() external onlyRole(ADMIN_ROLE) nonReentrant {
        renounceRole(ADMIN_ROLE, msg.sender);
        renounceRole(DEFAULT_ADMIN_ROLE, msg.sender);
        renounceRole(MINT_ROLE, msg.sender);
    }

    // --- Reward pool management ---
    function _refillRewardPool(uint256 neededReward) internal {
        uint256 current = rewardPool;
        if (current >= neededReward) return;

        uint256 shortfall = neededReward - current;
        uint256 minted;
        uint256 reclaimed;

        uint256 mintable = MAX_SUPPLY - totalSupply();
        if (mintable > 0) {
            uint256 toMint = shortfall > mintable ? mintable : shortfall;
            _mint(address(this), toMint);
            rewardPool += toMint;
            minted = toMint;
            if (rewardPool >= neededReward) {
                emit RewardPoolRefilled(neededReward, minted, reclaimed);
                return;
            }
            shortfall = neededReward - rewardPool;
        }

        if (depositBalance > 0 && shortfall > 0) {
            uint256 reclaim = shortfall > depositBalance ? depositBalance : shortfall;
            require(balanceOf(address(this)) >= reclaim);
            depositBalance -= reclaim;
            rewardPool += reclaim;
            reclaimed = reclaim;
        }

        emit RewardPoolRefilled(neededReward, minted, reclaimed);
        require(rewardPool >= neededReward);
    }

    function claimReward() external nonReentrant {
        require(rewardsActive);
        uint256 holderBal = balanceOf(msg.sender);
        require(holderBal > 0);

        uint256 last = lastClaimed[msg.sender];
        if (last == 0) {
            lastClaimed[msg.sender] = block.timestamp;
            emit ClaimInitialized(msg.sender, block.timestamp);
            return;
        }

        uint256 elapsed = block.timestamp - last;
        require(elapsed >= 1 days);

        uint256 reward = (holderBal * rewardAPYBps * elapsed) / (10_000 * 365 days);
        _refillRewardPool(reward);
        require(rewardPool >= reward);

        lastClaimed[msg.sender] = block.timestamp;
        rewardPool -= reward;
        _transfer(address(this), msg.sender, reward);
        emit RewardClaimed(msg.sender, reward);
    }

    function setRewardsActive(bool _active) external onlyRole(ADMIN_ROLE) nonReentrant {
        rewardsActive = _active;
        emit RewardsToggled(_active);
    }

    function setBurnPaused(bool _paused) external onlyRole(ADMIN_ROLE) {
        burnPaused = _paused;
        emit BurnPaused(_paused);
    }


    // ----Manually add tokens to Reward Pool------
function addToRewardPool(uint256 amount)
    external
    onlyRole(ADMIN_ROLE)
    nonReentrant
{
    require(amount > 0, "Invalid amount");
    require(balanceOf(msg.sender) >= amount, "Insufficient balance");

    _transfer(msg.sender, address(this), amount);
    rewardPool += amount;

    emit RewardPoolRefilled(0, 0, amount); // mark as manual refill
}

}
