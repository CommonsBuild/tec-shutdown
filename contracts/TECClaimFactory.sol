// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IMiniMeToken} from "./TECClaim.sol";

/**
 * @title TECClaimFactory
 * @notice Factory contract for creating TECClaim proxies
 */
contract TECClaimFactory {
    address public immutable implementation;

    event ProxyCreated(address indexed proxy, address indexed implementation);

    /**
     * @notice Constructor that sets the TECClaim implementation address
     * @param _implementation The address of the TECClaim implementation contract
     */
    constructor(address _implementation) {
        implementation = _implementation;
    }

    /**
     * @notice Creates a new ERC1967Proxy pointing to the TECClaim implementation
     * @param initialOwner The initial owner of the TECClaim contract
     * @param token The MiniMe token to create a snapshot from
     * @param redeemableTokens Array of tokens that can be redeemed
     * @param claimDeadline The deadline for claiming tokens
     * @return proxy The address of the newly created proxy
     */
    function create(
        address initialOwner,
        IMiniMeToken token,
        IERC20[] memory redeemableTokens,
        uint64 claimDeadline
    ) external returns (address proxy) {
        bytes memory data = abi.encodeWithSignature(
            "initialize(address,address,address[],uint64)",
            initialOwner,
            token,
            redeemableTokens,
            claimDeadline
        );
        proxy = address(new ERC1967Proxy(implementation, data));
        emit ProxyCreated(proxy, implementation);
    }
}

