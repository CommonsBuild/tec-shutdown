// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.28;

import {TECClaim, ITokenManager, IERC20} from "./TECClaim.sol";
import {Test, console2} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Mock ERC20 Token
contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory _name, string memory _symbol, uint256 _totalSupply) {
        name = _name;
        symbol = _symbol;
        totalSupply = _totalSupply;
        balanceOf[msg.sender] = _totalSupply;
        emit Transfer(address(0), msg.sender, _totalSupply);
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        emit Transfer(from, to, amount);
        return true;
    }

    function mint(address to, uint256 amount) public {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function burn(address from, uint256 amount) public {
        require(balanceOf[from] >= amount, "Insufficient balance");
        balanceOf[from] -= amount;
        totalSupply -= amount;
        emit Transfer(from, address(0), amount);
    }
}

// Mock Token Manager
contract MockTokenManager is ITokenManager {
    MockERC20 public tecToken;
    address public owner;

    constructor(uint256 initialSupply) {
        owner = msg.sender;
        tecToken = new MockERC20("Token Engineering Commons", "TEC", initialSupply);
    }

    function burn(address account, uint256 amount) external override {
        tecToken.burn(account, amount);
    }

    function token() external view override returns (address) {
        return address(tecToken);
    }

    function mint(address to, uint256 amount) external {
        tecToken.mint(to, amount);
    }

    function transfer(address to, uint256 amount) external {
        tecToken.transfer(to, amount);
    }
}

contract TECClaimTest is Test {
    TECClaim public claim;
    MockTokenManager public tokenManager;
    MockERC20 public dai;
    MockERC20 public reth;
    MockERC20 public tecToken;

    address public owner = address(this);
    address public user1 = address(0x1);
    address public user2 = address(0x2);
    address public user3 = address(0x3);

    uint256 constant DAI_AMOUNT = 100_000e18; // 100k DAI
    uint256 constant RETH_AMOUNT = 16e18; // 16 RETH
    uint256 constant TEC_TOTAL_SUPPLY = 1_136_450e18; // 1,136,450 TEC
    uint64 constant CLAIM_DEADLINE = 365 days;

    event Claim(address indexed user, uint256 amount);
    event ClaimRemaining(address indexed owner);
    event AddressBlocked(address indexed user);
    event AddressUnblocked(address indexed user);

    function setUp() public {
        // Create mock tokens
        dai = new MockERC20("DAI Stablecoin", "DAI", DAI_AMOUNT);
        reth = new MockERC20("Rocket Pool ETH", "RETH", RETH_AMOUNT);
        
        // Create mock token manager with TEC token
        tokenManager = new MockTokenManager(TEC_TOTAL_SUPPLY);
        tecToken = MockERC20(tokenManager.token());

        // Deploy TECClaim implementation
        TECClaim implementation = new TECClaim();

        // Prepare initialization data
        IERC20[] memory redeemableTokens = new IERC20[](2);
        redeemableTokens[0] = IERC20(address(dai));
        redeemableTokens[1] = IERC20(address(reth));
        
        bytes memory initData = abi.encodeWithSelector(
            TECClaim.initialize.selector,
            owner,
            ITokenManager(address(tokenManager)),
            redeemableTokens,
            uint64(block.timestamp + CLAIM_DEADLINE)
        );

        // Deploy proxy and initialize
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        claim = TECClaim(address(proxy));

        // Transfer redeemable tokens to claim contract
        dai.transfer(address(claim), DAI_AMOUNT);
        reth.transfer(address(claim), RETH_AMOUNT);

        // Activate the claim contract (transition from configured to active)
        address[] memory emptyAddresses = new address[](0);
        claim.startClaim(emptyAddresses);

        // Distribute TEC tokens to users (tokens are in tokenManager initially)
        tokenManager.transfer(user1, 500_000e18); // ~44% of supply
        tokenManager.transfer(user2, 300_000e18); // ~26% of supply
        tokenManager.transfer(user3, 100_000e18); // ~8.8% of supply
        tokenManager.transfer(owner, 236_450e18); // ~20.8% of supply
    }

    function test_Initialize() public view {
        assertEq(claim.owner(), owner);
        assertEq(claim.claimDeadline(), block.timestamp + CLAIM_DEADLINE);
        assertEq(dai.balanceOf(address(claim)), DAI_AMOUNT);
        assertEq(reth.balanceOf(address(claim)), RETH_AMOUNT);
        assertEq(uint8(claim.state()), uint8(2)); // State.active (after startClaim in setUp)
    }

    function test_InitialStateIsConfiguredBeforeStart() public {
        // Create a new claim contract and check its initial state
        TECClaim implementation = new TECClaim();
        IERC20[] memory redeemableTokens = new IERC20[](2);
        redeemableTokens[0] = IERC20(address(dai));
        redeemableTokens[1] = IERC20(address(reth));
        
        bytes memory initData = abi.encodeWithSelector(
            TECClaim.initialize.selector,
            owner,
            ITokenManager(address(tokenManager)),
            redeemableTokens,
            uint64(block.timestamp + CLAIM_DEADLINE)
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        TECClaim newClaim = TECClaim(address(proxy));
        
        // After initialization, state should be configured
        assertEq(uint8(newClaim.state()), 1); // State.configured
    }

    function test_StartClaimTransitionsToActive() public {
        // Create new tokens in separate addresses to transfer
        address tokenHolder1 = address(0x101);
        address tokenHolder2 = address(0x102);
        
        // Create new token instances for this test
        MockERC20 newDai = new MockERC20("DAI", "DAI", 50_000e18);
        MockERC20 newReth = new MockERC20("RETH", "RETH", 10e18);
        
        // Transfer to holders
        newDai.transfer(tokenHolder1, 25_000e18);
        newDai.transfer(tokenHolder2, 25_000e18);
        newReth.transfer(tokenHolder1, 5e18);
        newReth.transfer(tokenHolder2, 5e18);
        
        // Create new claim contract for this test
        TECClaim implementation = new TECClaim();
        IERC20[] memory redeemableTokens = new IERC20[](2);
        redeemableTokens[0] = IERC20(address(newDai));
        redeemableTokens[1] = IERC20(address(newReth));
        
        bytes memory initData = abi.encodeWithSelector(
            TECClaim.initialize.selector,
            owner,
            ITokenManager(address(tokenManager)),
            redeemableTokens,
            uint64(block.timestamp + CLAIM_DEADLINE)
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        TECClaim newClaim = TECClaim(address(proxy));
        
        // Approve tokens for transfer
        vm.prank(tokenHolder1);
        newDai.approve(address(newClaim), type(uint256).max);
        vm.prank(tokenHolder1);
        newReth.approve(address(newClaim), type(uint256).max);
        
        vm.prank(tokenHolder2);
        newDai.approve(address(newClaim), type(uint256).max);
        vm.prank(tokenHolder2);
        newReth.approve(address(newClaim), type(uint256).max);
        
        // Prepare startClaim parameters
        address[] memory holders = new address[](2);
        holders[0] = tokenHolder1;
        holders[1] = tokenHolder2;
        
        // State should be configured
        assertEq(uint8(newClaim.state()), 1);
        
        // Call startClaim
        newClaim.startClaim(holders);
        
        // State should now be active
        assertEq(uint8(newClaim.state()), 2); // State.active
        
        // Verify tokens were transferred
        assertEq(newDai.balanceOf(address(newClaim)), 50_000e18);
        assertEq(newReth.balanceOf(address(newClaim)), 10e18);
        assertEq(newDai.balanceOf(tokenHolder1), 0);
        assertEq(newDai.balanceOf(tokenHolder2), 0);
    }

    function test_RevertWhen_StartClaimNotOwner() public {
        address[] memory holders = new address[](1);
        holders[0] = address(this);
        
        vm.prank(user1);
        vm.expectRevert();
        claim.startClaim(holders);
    }

    function test_RevertWhen_StartClaimNotConfigured() public {
        // Create claim contract and start it
        address tokenHolder = address(0x103);
        MockERC20 newDai = new MockERC20("DAI", "DAI", 50_000e18);
        newDai.transfer(tokenHolder, 50_000e18);
        
        TECClaim implementation = new TECClaim();
        IERC20[] memory redeemableTokens = new IERC20[](1);
        redeemableTokens[0] = IERC20(address(newDai));
        
        bytes memory initData = abi.encodeWithSelector(
            TECClaim.initialize.selector,
            owner,
            ITokenManager(address(tokenManager)),
            redeemableTokens,
            uint64(block.timestamp + CLAIM_DEADLINE)
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        TECClaim newClaim = TECClaim(address(proxy));
        
        vm.prank(tokenHolder);
        newDai.approve(address(newClaim), type(uint256).max);
        
        address[] memory holders = new address[](1);
        holders[0] = tokenHolder;
        
        // Start claim once
        newClaim.startClaim(holders);
        assertEq(uint8(newClaim.state()), 2); // State.active
        
        // Try to start claim again - should revert
        vm.expectRevert(TECClaim.ErrorNotConfigured.selector);
        newClaim.startClaim(holders);
    }

    function test_RevertWhen_ClaimBeforeActive() public {
        // Create a new claim contract that hasn't been started
        TECClaim implementation = new TECClaim();
        IERC20[] memory redeemableTokens = new IERC20[](2);
        redeemableTokens[0] = IERC20(address(dai));
        redeemableTokens[1] = IERC20(address(reth));
        
        bytes memory initData = abi.encodeWithSelector(
            TECClaim.initialize.selector,
            owner,
            ITokenManager(address(tokenManager)),
            redeemableTokens,
            uint64(block.timestamp + CLAIM_DEADLINE)
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        TECClaim newClaim = TECClaim(address(proxy));
        
        // State should be configured
        assertEq(uint8(newClaim.state()), 1);
        
        // Try to claim - should revert
        vm.prank(user1);
        vm.expectRevert(TECClaim.ErrorNotActive.selector);
        newClaim.claim();
    }

    function test_ClaimRemainingTransitionsToFinalized() public {
        // User1 claims
        vm.prank(user1);
        claim.claim();
        
        // Fast forward past deadline
        vm.warp(block.timestamp + CLAIM_DEADLINE + 1);
        
        // State should be active
        assertEq(uint8(claim.state()), 2);
        
        // Claim remaining
        claim.claimRemaining();
        
        // State should now be finalized
        assertEq(uint8(claim.state()), 3); // State.finialized
    }

    function test_RevertWhen_ClaimRemainingNotActive() public {
        // Create new claim contract and don't start it
        TECClaim implementation = new TECClaim();
        IERC20[] memory redeemableTokens = new IERC20[](2);
        redeemableTokens[0] = IERC20(address(dai));
        redeemableTokens[1] = IERC20(address(reth));
        
        bytes memory initData = abi.encodeWithSelector(
            TECClaim.initialize.selector,
            owner,
            ITokenManager(address(tokenManager)),
            redeemableTokens,
            uint64(block.timestamp + CLAIM_DEADLINE)
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        TECClaim newClaim = TECClaim(address(proxy));
        
        // Fast forward past deadline
        vm.warp(block.timestamp + CLAIM_DEADLINE + 1);
        
        // Try to claim remaining - should revert because not active
        vm.expectRevert(TECClaim.ErrorNotActive.selector);
        newClaim.claimRemaining();
    }

    function test_StartClaimWithMultipleTokensAndHolders() public {
        address holder1 = address(0x201);
        address holder2 = address(0x202);
        address holder3 = address(0x203);
        
        MockERC20 token1 = new MockERC20("Token1", "TK1", 300e18);
        MockERC20 token2 = new MockERC20("Token2", "TK2", 600e18);
        MockERC20 token3 = new MockERC20("Token3", "TK3", 900e18);
        
        // Distribute tokens to holders
        token1.transfer(holder1, 100e18);
        token1.transfer(holder2, 100e18);
        token1.transfer(holder3, 100e18);
        
        token2.transfer(holder1, 200e18);
        token2.transfer(holder2, 200e18);
        token2.transfer(holder3, 200e18);
        
        token3.transfer(holder1, 300e18);
        token3.transfer(holder2, 300e18);
        token3.transfer(holder3, 300e18);
        
        // Create new claim contract
        TECClaim implementation = new TECClaim();
        IERC20[] memory redeemableTokens = new IERC20[](3);
        redeemableTokens[0] = IERC20(address(token1));
        redeemableTokens[1] = IERC20(address(token2));
        redeemableTokens[2] = IERC20(address(token3));
        
        bytes memory initData = abi.encodeWithSelector(
            TECClaim.initialize.selector,
            owner,
            ITokenManager(address(tokenManager)),
            redeemableTokens,
            uint64(block.timestamp + CLAIM_DEADLINE)
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        TECClaim newClaim = TECClaim(address(proxy));
        
        // Approve all tokens
        vm.prank(holder1);
        token1.approve(address(newClaim), type(uint256).max);
        vm.prank(holder1);
        token2.approve(address(newClaim), type(uint256).max);
        vm.prank(holder1);
        token3.approve(address(newClaim), type(uint256).max);
        
        vm.prank(holder2);
        token1.approve(address(newClaim), type(uint256).max);
        vm.prank(holder2);
        token2.approve(address(newClaim), type(uint256).max);
        vm.prank(holder2);
        token3.approve(address(newClaim), type(uint256).max);
        
        vm.prank(holder3);
        token1.approve(address(newClaim), type(uint256).max);
        vm.prank(holder3);
        token2.approve(address(newClaim), type(uint256).max);
        vm.prank(holder3);
        token3.approve(address(newClaim), type(uint256).max);
        
        // Prepare startClaim parameters
        address[] memory holders = new address[](3);
        holders[0] = holder1;
        holders[1] = holder2;
        holders[2] = holder3;
        
        // Call startClaim
        newClaim.startClaim(holders);
        
        // Verify all tokens were transferred
        assertEq(token1.balanceOf(address(newClaim)), 300e18);
        assertEq(token2.balanceOf(address(newClaim)), 600e18);
        assertEq(token3.balanceOf(address(newClaim)), 900e18);
        
        // Verify state is active
        assertEq(uint8(newClaim.state()), 2);
    }

    function test_ClaimProportionalDistribution() public {
        uint256 user1TecBalance = tecToken.balanceOf(user1);
        uint256 tecTotalSupply = tecToken.totalSupply();
        
        // Calculate expected amounts
        uint256 expectedDai = (user1TecBalance * DAI_AMOUNT) / tecTotalSupply;
        uint256 expectedReth = (user1TecBalance * RETH_AMOUNT) / tecTotalSupply;

        vm.startPrank(user1);
        
        vm.expectEmit(true, false, false, true);
        emit Claim(user1, user1TecBalance);
        
        claim.claim();
        vm.stopPrank();

        // Check user received correct proportional amounts
        assertEq(dai.balanceOf(user1), expectedDai);
        assertEq(reth.balanceOf(user1), expectedReth);
        
        // Check TEC tokens were burned
        assertEq(tecToken.balanceOf(user1), 0);
        assertEq(tecToken.totalSupply(), tecTotalSupply - user1TecBalance);
    }

    function test_ClaimMultipleUsers() public {
        uint256 initialDaiBalance = dai.balanceOf(address(claim));
        uint256 initialRethBalance = reth.balanceOf(address(claim));

        // User1 claims
        vm.prank(user1);
        claim.claim();

        // User2 claims
        vm.prank(user2);
        claim.claim();

        // Check both users received tokens
        assertGt(dai.balanceOf(user1), 0);
        assertGt(dai.balanceOf(user2), 0);
        assertGt(reth.balanceOf(user1), 0);
        assertGt(reth.balanceOf(user2), 0);

        // Check claim contract balances decreased
        assertLt(dai.balanceOf(address(claim)), initialDaiBalance);
        assertLt(reth.balanceOf(address(claim)), initialRethBalance);

        // Check TEC tokens were burned
        assertEq(tecToken.balanceOf(user1), 0);
        assertEq(tecToken.balanceOf(user2), 0);
    }

    function test_ClaimAllUsers() public {
        // All users claim
        vm.prank(user1);
        claim.claim();
        
        vm.prank(user2);
        claim.claim();
        
        vm.prank(user3);
        claim.claim();
        
        vm.prank(owner);
        claim.claim();

        // Check all TEC tokens were burned
        assertEq(tecToken.totalSupply(), 0);
        
        // Check all redeemable tokens were distributed
        assertEq(dai.balanceOf(address(claim)), 0);
        assertEq(reth.balanceOf(address(claim)), 0);
    }

    function test_RevertWhen_ClaimWithZeroBalance() public {
        address userWithNoTokens = address(0x999);
        
        vm.prank(userWithNoTokens);
        vm.expectRevert(TECClaim.ErrorCannotBurnZero.selector);
        claim.claim();
    }

    function test_RevertWhen_ClaimAfterAlreadyClaimed() public {
        vm.startPrank(user1);
        claim.claim();
        
        vm.expectRevert(TECClaim.ErrorCannotBurnZero.selector);
        claim.claim();
        vm.stopPrank();
    }

    function test_RevertWhen_ClaimAddressBlocked() public {
        // Block user1
        address[] memory usersToBlock = new address[](1);
        usersToBlock[0] = user1;
        claim.blockAddresses(usersToBlock);

        vm.prank(user1);
        vm.expectRevert(TECClaim.ErrorAddressBlocked.selector);
        claim.claim();
    }

    function test_BlockAddresses() public {
        address[] memory usersToBlock = new address[](2);
        usersToBlock[0] = user1;
        usersToBlock[1] = user2;

        vm.expectEmit(true, false, false, false);
        emit AddressBlocked(user1);
        vm.expectEmit(true, false, false, false);
        emit AddressBlocked(user2);
        
        claim.blockAddresses(usersToBlock);

        assertTrue(claim.blocklist(user1));
        assertTrue(claim.blocklist(user2));
        assertFalse(claim.blocklist(user3));
    }

    function test_UnblockAddresses() public {
        // First block addresses
        address[] memory usersToBlock = new address[](1);
        usersToBlock[0] = user1;
        claim.blockAddresses(usersToBlock);
        assertTrue(claim.blocklist(user1));

        // Then unblock
        vm.expectEmit(true, false, false, false);
        emit AddressUnblocked(user1);
        
        claim.unblockAddresses(usersToBlock);
        assertFalse(claim.blocklist(user1));
    }

    function test_ClaimAfterUnblocked() public {
        // Block user1
        address[] memory users = new address[](1);
        users[0] = user1;
        claim.blockAddresses(users);

        // Unblock user1
        claim.unblockAddresses(users);

        // User1 should be able to claim now
        vm.prank(user1);
        claim.claim();

        assertEq(tecToken.balanceOf(user1), 0);
        assertGt(dai.balanceOf(user1), 0);
    }

    function test_RevertWhen_BlockAddressesNotOwner() public {
        address[] memory users = new address[](1);
        users[0] = user1;

        vm.prank(user1);
        vm.expectRevert();
        claim.blockAddresses(users);
    }

    function test_RevertWhen_UnblockAddressesNotOwner() public {
        address[] memory users = new address[](1);
        users[0] = user1;

        vm.prank(user1);
        vm.expectRevert();
        claim.unblockAddresses(users);
    }

    function test_ClaimRemaining() public {
        // Some users claim
        vm.prank(user1);
        claim.claim();

        vm.prank(user2);
        claim.claim();

        // Fast forward past deadline
        vm.warp(block.timestamp + CLAIM_DEADLINE + 1);

        uint256 remainingDai = dai.balanceOf(address(claim));
        uint256 remainingReth = reth.balanceOf(address(claim));

        vm.expectEmit(true, false, false, false);
        emit ClaimRemaining(owner);

        claim.claimRemaining();

        // Check owner received remaining tokens
        assertEq(dai.balanceOf(owner), remainingDai);
        assertEq(reth.balanceOf(owner), remainingReth);
        assertEq(dai.balanceOf(address(claim)), 0);
        assertEq(reth.balanceOf(address(claim)), 0);
    }

    function test_RevertWhen_ClaimRemainingBeforeDeadline() public {
        vm.expectRevert(TECClaim.ErrorClaimDeadlineNotReachedYet.selector);
        claim.claimRemaining();
    }

    function test_RevertWhen_ClaimRemainingNotOwner() public {
        vm.warp(block.timestamp + CLAIM_DEADLINE + 1);

        vm.prank(user1);
        vm.expectRevert();
        claim.claimRemaining();
    }

    function test_ClaimWithSingleRedeemableToken() public {
        // Create a new mock token and token manager for isolated test
        MockTokenManager newTokenManager = new MockTokenManager(1_000_000e18);
        MockERC20 newTecToken = MockERC20(newTokenManager.token());
        
        // Create a new claim contract with only DAI
        TECClaim implementation = new TECClaim();
        IERC20[] memory redeemableTokens = new IERC20[](1);
        
        // Create new DAI for this test
        MockERC20 newDai = new MockERC20("DAI", "DAI", 50_000e18);
        redeemableTokens[0] = IERC20(address(newDai));

        bytes memory initData = abi.encodeWithSelector(
            TECClaim.initialize.selector,
            owner,
            ITokenManager(address(newTokenManager)),
            redeemableTokens,
            uint64(block.timestamp + CLAIM_DEADLINE)
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        TECClaim singleTokenClaim = TECClaim(address(proxy));
        
        // Transfer DAI to claim contract
        newDai.transfer(address(singleTokenClaim), 50_000e18);

        // Activate the claim contract
        address[] memory emptyAddresses = new address[](0);
        singleTokenClaim.startClaim(emptyAddresses);

        // Give user some TEC tokens
        address testUser = address(0x888);
        newTokenManager.transfer(testUser, 100_000e18);

        vm.prank(testUser);
        singleTokenClaim.claim();

        assertGt(newDai.balanceOf(testUser), 0);
        assertEq(newTecToken.balanceOf(testUser), 0); // TEC tokens should be burned
    }

    function test_ProportionalDistributionAccuracy() public {
        uint256 user1TecBalance = tecToken.balanceOf(user1);
        uint256 tecTotalSupply = tecToken.totalSupply();
        
        uint256 expectedDai = (user1TecBalance * DAI_AMOUNT) / tecTotalSupply;
        uint256 expectedReth = (user1TecBalance * RETH_AMOUNT) / tecTotalSupply;

        vm.prank(user1);
        claim.claim();

        // Allow for rounding error of 1 wei
        assertApproxEqAbs(dai.balanceOf(user1), expectedDai, 1);
        assertApproxEqAbs(reth.balanceOf(user1), expectedReth, 1);
    }

    function test_ClaimEmitsCorrectEvent() public {
        uint256 user1Balance = tecToken.balanceOf(user1);

        vm.expectEmit(true, false, false, true);
        emit Claim(user1, user1Balance);

        vm.prank(user1);
        claim.claim();
    }

    function test_RemainingTokensAfterPartialClaims() public {
        // Only user3 claims (smallest holder)
        vm.prank(user3);
        claim.claim();

        uint256 remainingDai = dai.balanceOf(address(claim));
        uint256 remainingReth = reth.balanceOf(address(claim));

        // Remaining should be close to original minus user3's share
        uint256 expectedRemainingDai = DAI_AMOUNT - ((100_000e18 * DAI_AMOUNT) / TEC_TOTAL_SUPPLY);
        
        assertApproxEqAbs(remainingDai, expectedRemainingDai, 100);
        assertGt(remainingDai, 0);
        assertGt(remainingReth, 0);
    }
}
