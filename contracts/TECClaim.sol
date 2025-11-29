// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

interface IMiniMeToken is IERC20 {
    function controller() external returns(address);
    function destroyTokens(address _owner, uint _amount) external returns (bool);
    function createCloneToken(
        string memory _cloneTokenName,
        uint8 _cloneDecimalUnits,
        string memory _cloneTokenSymbol,
        uint _snapshotBlock,
        bool _transfersEnabled
    ) external returns(IMiniMeToken);
}

enum State {
    dormant,
    configured,
    active,
    finialized
}

contract TECClaim is Initializable, UUPSUpgradeable, OwnableUpgradeable {
  using SafeERC20 for IERC20;

    State public state;
    IMiniMeToken public token;
    uint64 public claimDeadline;
    IERC20[] public redeemableTokens;
    mapping(address => bool) public blocklist;

    error ErrorCannotBurnZero();
    error ErrorInsufficientBalance();
    error ErrorCannotRedeemZero();
    error ErrorClaimDeadlineNotReachedYet();
    error ErrorAddressBlocked();
    error ErrorNotConfigured();
    error ErrorNotActive();
    error ErrorAlreadyActive();

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
        IMiniMeToken _token,
        IERC20[] memory _redeemableTokens,
        uint64 _claimDeadline
    ) public initializer {
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();
        token = _token.createCloneToken("TEC Shutdown Snapshot", 18, "TECSNAP", block.number, false);
        redeemableTokens = _redeemableTokens;
        claimDeadline = _claimDeadline;
        state = State.configured;
    }

    function burn(address _owner, uint256 _amount) external onlyOwner {
        if (state != State.configured) {
            revert ErrorAlreadyActive();
        }

        token.destroyTokens(_owner, _amount);
    }

    function startClaim(address[] calldata from) external onlyOwner {
        if (state != State.configured) {
            revert ErrorNotConfigured();
        }

        for (uint i = 0; i < redeemableTokens.length; i++) {
            for (uint j = 0; j < from.length; j++) {
                uint256 balance = redeemableTokens[i].balanceOf(from[j]);
                if (balance > 0) {
                    redeemableTokens[i].safeTransferFrom(from[j], address(this), balance);
                }
            }
        }
        state = State.active;
    }

    function claim() external {
        if (state != State.active) {
            revert ErrorNotActive();
        }

        if (blocklist[msg.sender]) {
            revert ErrorAddressBlocked();
        }

        uint256 burnableAmount = token.balanceOf(msg.sender);
        uint256 burnableTokenTotalSupply = token.totalSupply();
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

        token.destroyTokens(msg.sender, burnableAmount);

        emit Claim(msg.sender, burnableAmount);
    }

    function claimRemaining() external onlyOwner {
        if (state != State.active) {
            revert ErrorNotActive();
        }

        if (block.timestamp < claimDeadline) {
            revert ErrorClaimDeadlineNotReachedYet();
        }

        for (uint256 i = 0; i < redeemableTokens.length; i++) {
            redeemableTokens[i].safeTransfer(msg.sender, redeemableTokens[i].balanceOf(address(this)));
        }

        state = State.finialized;

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
