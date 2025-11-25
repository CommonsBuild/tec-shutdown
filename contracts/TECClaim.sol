// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

interface ITokenManager {
    function burn(address account, uint256 amount) external;
    function token() external view returns (address);
}

contract TECClaim is Initializable, UUPSUpgradeable, OwnableUpgradeable {
  using SafeERC20 for IERC20;

    ITokenManager internal tokenManager;
    IERC20[] internal redeemableTokens;
    uint64 public claimDeadline;
    mapping(address => bool) public blocklist;

    error ErrorCannotBurnZero();
    error ErrorInsufficientBalance();
    error ErrorCannotRedeemZero();
    error ErrorClaimDeadlineNotReachedYet();
    error ErrorAddressBlocked();

    event Claim(address indexed user, uint256 amount);
    event ClaimRemaining(address indexed owner);
    event AddressBlocked(address indexed user);
    event AddressUnblocked(address indexed user);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address initialOwner,
        ITokenManager _tokenManager,
        IERC20[] memory _redeemableTokens,
        uint64 _claimDeadline
    ) public initializer {
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();
        tokenManager = _tokenManager;
        redeemableTokens = _redeemableTokens;
        claimDeadline = _claimDeadline;
    }

    function claim() external {
        if (blocklist[msg.sender]) {
            revert ErrorAddressBlocked();
        }

        uint256 burnableAmount = IERC20(tokenManager.token()).balanceOf(msg.sender);
        uint256 burnableTokenTotalSupply = IERC20(tokenManager.token()).totalSupply();
        uint256 redemptionAmount;
        uint256 totalRedemptionAmount;
        uint256 vaultTokenBalance;

        if (burnableAmount == 0) {
            revert ErrorCannotBurnZero();
        }

        for (uint256 i = 0; i < redeemableTokens.length; i++) {
            vaultTokenBalance = redeemableTokens[i].balanceOf(address(this));

            redemptionAmount = burnableAmount * vaultTokenBalance / burnableTokenTotalSupply;
            totalRedemptionAmount += redemptionAmount;

            if (redemptionAmount > 0) {
                redeemableTokens[i].safeTransfer(msg.sender, redemptionAmount);
            }
        }

        if (totalRedemptionAmount == 0) {
            revert ErrorCannotRedeemZero();
        }

        tokenManager.burn(msg.sender, burnableAmount);

        emit Claim(msg.sender, burnableAmount);
    }

    function claimRemaining() external onlyOwner {
        if (block.timestamp < claimDeadline) {
            revert ErrorClaimDeadlineNotReachedYet();
        }

        for (uint256 i = 0; i < redeemableTokens.length; i++) {
            redeemableTokens[i].safeTransfer(msg.sender, redeemableTokens[i].balanceOf(address(this)));
        }

        emit ClaimRemaining(msg.sender);
    }

    function blockAddresses(address[] calldata users) external onlyOwner {
        for (uint256 i = 0; i < users.length; i++) {
            blocklist[users[i]] = true;
            emit AddressBlocked(users[i]);
        }
    }

    function unblockAddresses(address[] calldata users) external onlyOwner {
        for (uint256 i = 0; i < users.length; i++) {
            blocklist[users[i]] = false;
            emit AddressUnblocked(users[i]);
        }
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
