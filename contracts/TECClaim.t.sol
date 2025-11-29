// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.28;

import {TECClaim, IMiniMeToken, IERC20} from "./TECClaim.sol";
import {Test, console2} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Mock ERC20 Token (for DAI, RETH, etc.)
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

// Mock MiniMe Token (simplified version for testing)
contract MockMiniMeToken {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    address public controller;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event CloneTokenCreated(address indexed clone);

    constructor(string memory _name, string memory _symbol, uint256 _totalSupply) {
        name = _name;
        symbol = _symbol;
        totalSupply = _totalSupply;
        balanceOf[msg.sender] = _totalSupply;
        controller = msg.sender;
        emit Transfer(address(0), msg.sender, _totalSupply);
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function destroyTokens(address _owner, uint256 _amount) external returns (bool) {
        require(msg.sender == controller, "Only controller can destroy tokens");
        require(balanceOf[_owner] >= _amount, "Insufficient balance");
        balanceOf[_owner] -= _amount;
        totalSupply -= _amount;
        emit Transfer(_owner, address(0), _amount);
        return true;
    }

    function createCloneToken(
        string memory _cloneTokenName,
        uint8 /* _cloneDecimalUnits */,
        string memory _cloneTokenSymbol,
        uint256 /* _snapshotBlock */,
        bool /* _transfersEnabled */
    ) external returns (IMiniMeToken) {
        MockMiniMeTokenClone clone = new MockMiniMeTokenClone(
            _cloneTokenName,
            _cloneTokenSymbol,
            address(this)
        );
        clone.setController(msg.sender);
        
        // Copy current totalSupply
        clone.setTotalSupply(totalSupply);
        
        // Copy all existing balances to the clone
        // This happens implicitly through the snapshot mechanism
        // We use the parent field to track where balances come from
        
        emit CloneTokenCreated(address(clone));
        return IMiniMeToken(address(clone));
    }

    function copyBalanceToClone(address clone, address holder) external {
        MockMiniMeTokenClone(clone).mint(holder, balanceOf[holder]);
    }
}

// Mock MiniMe Token Clone (simplified version for testing)
contract MockMiniMeTokenClone {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) private _balanceOverrides;
    mapping(address => bool) private _hasBalanceOverride;
    address public controller;
    address public parentToken;

    event Transfer(address indexed from, address indexed to, uint256 value);

    constructor(string memory _name, string memory _symbol, address _parentToken) {
        name = _name;
        symbol = _symbol;
        parentToken = _parentToken;
    }

    function setController(address _controller) external {
        controller = _controller;
    }

    function setTotalSupply(uint256 _totalSupply) external {
        totalSupply = _totalSupply;
    }

    function balanceOf(address _owner) public view returns (uint256) {
        // If balance was overridden (burned or minted), use override
        if (_hasBalanceOverride[_owner]) {
            return _balanceOverrides[_owner];
        }
        // Otherwise, query parent token
        if (parentToken != address(0)) {
            return MockMiniMeToken(parentToken).balanceOf(_owner);
        }
        return 0;
    }

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        _balanceOverrides[to] = balanceOf(to) + amount;
        _hasBalanceOverride[to] = true;
        emit Transfer(address(0), to, amount);
    }

    function destroyTokens(address _owner, uint256 _amount) external returns (bool) {
        require(msg.sender == controller, "Only controller can destroy tokens");
        uint256 currentBalance = balanceOf(_owner);
        require(currentBalance >= _amount, "Insufficient balance");
        
        _balanceOverrides[_owner] = currentBalance - _amount;
        _hasBalanceOverride[_owner] = true;
        totalSupply -= _amount;
        
        emit Transfer(_owner, address(0), _amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        uint256 senderBalance = balanceOf(msg.sender);
        require(senderBalance >= amount, "Insufficient balance");
        
        _balanceOverrides[msg.sender] = senderBalance - amount;
        _hasBalanceOverride[msg.sender] = true;
        
        uint256 recipientBalance = balanceOf(to);
        _balanceOverrides[to] = recipientBalance + amount;
        _hasBalanceOverride[to] = true;
        
        emit Transfer(msg.sender, to, amount);
        return true;
    }
}

contract TECClaimTest is Test {
    TECClaim public claim;
    MockMiniMeToken public sourceTecToken;      // Source token to create snapshot from
    MockMiniMeTokenClone public snapshotToken;       // Snapshot token created by contract
    MockERC20 public dai;
    MockERC20 public reth;

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
        // Create mock tokens for redeemables
        dai = new MockERC20("DAI Stablecoin", "DAI", DAI_AMOUNT);
        reth = new MockERC20("Rocket Pool ETH", "RETH", RETH_AMOUNT);
        
        // Create source MiniMe token (original TEC token with balances)
        sourceTecToken = new MockMiniMeToken(
            "Token Engineering Commons",
            "TEC",
            TEC_TOTAL_SUPPLY
        );
        
        // Distribute TEC tokens to users in the SOURCE token
        // These balances will be snapshotted when the contract initializes
        sourceTecToken.transfer(user1, 500_000e18); // ~44% of supply
        sourceTecToken.transfer(user2, 300_000e18); // ~26% of supply
        sourceTecToken.transfer(user3, 100_000e18); // ~8.8% of supply
        // owner keeps 236_450e18 (~20.8% of supply)

        // Deploy TECClaim implementation
        TECClaim implementation = new TECClaim();

        // Prepare initialization data
        IERC20[] memory redeemableTokens = new IERC20[](2);
        redeemableTokens[0] = IERC20(address(dai));
        redeemableTokens[1] = IERC20(address(reth));
        
        bytes memory initData = abi.encodeWithSelector(
            TECClaim.initialize.selector,
            owner,
            IMiniMeToken(address(sourceTecToken)),
            redeemableTokens,
            uint64(block.timestamp + CLAIM_DEADLINE)
        );

        // Deploy proxy and initialize (this creates the snapshot)
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        claim = TECClaim(address(proxy));
        
        // Get reference to the snapshot token that was created
        // The contract creates the snapshot and stores it in the token variable
        snapshotToken = MockMiniMeTokenClone(address(claim.token()));

        // Transfer redeemable tokens to claim contract
        dai.transfer(address(claim), DAI_AMOUNT);
        reth.transfer(address(claim), RETH_AMOUNT);

        // Activate the claim contract (transition from configured to active)
        address[] memory emptyAddresses = new address[](0);
        claim.startClaim(emptyAddresses);
    }

    function test_Initialize() public view {
        assertEq(claim.owner(), owner);
        assertEq(claim.claimDeadline(), block.timestamp + CLAIM_DEADLINE);
        assertEq(dai.balanceOf(address(claim)), DAI_AMOUNT);
        assertEq(reth.balanceOf(address(claim)), RETH_AMOUNT);
        assertEq(uint8(claim.state()), uint8(2)); // State.active (after startClaim in setUp)
    }

    function test_InitialStateIsConfiguredBeforeStart() public {
        // Create a new source token and claim contract to check initial state
        MockMiniMeToken newSourceToken = new MockMiniMeToken(
            "TEC",
            "TEC",
            TEC_TOTAL_SUPPLY
        );
        
        TECClaim implementation = new TECClaim();
        IERC20[] memory redeemableTokens = new IERC20[](2);
        redeemableTokens[0] = IERC20(address(dai));
        redeemableTokens[1] = IERC20(address(reth));
        
        bytes memory initData = abi.encodeWithSelector(
            TECClaim.initialize.selector,
            owner,
            IMiniMeToken(address(newSourceToken)),
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
        
        // Create new source token for this test
        MockMiniMeToken newSourceToken = new MockMiniMeToken(
            "TEC",
            "TEC",
            1_000_000e18
        );
        
        // Create new claim contract for this test
        TECClaim implementation = new TECClaim();
        IERC20[] memory redeemableTokens = new IERC20[](2);
        redeemableTokens[0] = IERC20(address(newDai));
        redeemableTokens[1] = IERC20(address(newReth));
        
        bytes memory initData = abi.encodeWithSelector(
            TECClaim.initialize.selector,
            owner,
            IMiniMeToken(address(newSourceToken)),
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
        
        MockMiniMeToken newSourceToken = new MockMiniMeToken("TEC", "TEC", 1_000_000e18);
        
        TECClaim implementation = new TECClaim();
        IERC20[] memory redeemableTokens = new IERC20[](1);
        redeemableTokens[0] = IERC20(address(newDai));
        
        bytes memory initData = abi.encodeWithSelector(
            TECClaim.initialize.selector,
            owner,
            IMiniMeToken(address(newSourceToken)),
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
        MockMiniMeToken newSourceToken = new MockMiniMeToken("TEC", "TEC", 1_000_000e18);
        
        TECClaim implementation = new TECClaim();
        IERC20[] memory redeemableTokens = new IERC20[](2);
        redeemableTokens[0] = IERC20(address(dai));
        redeemableTokens[1] = IERC20(address(reth));
        
        bytes memory initData = abi.encodeWithSelector(
            TECClaim.initialize.selector,
            owner,
            IMiniMeToken(address(newSourceToken)),
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
        MockMiniMeToken newSourceToken = new MockMiniMeToken("TEC", "TEC", 1_000_000e18);
        
        TECClaim implementation = new TECClaim();
        IERC20[] memory redeemableTokens = new IERC20[](2);
        redeemableTokens[0] = IERC20(address(dai));
        redeemableTokens[1] = IERC20(address(reth));
        
        bytes memory initData = abi.encodeWithSelector(
            TECClaim.initialize.selector,
            owner,
            IMiniMeToken(address(newSourceToken)),
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
        
        // Create new source token for this test
        MockMiniMeToken newSourceToken = new MockMiniMeToken("TEC", "TEC", 1_000_000e18);
        
        // Create new claim contract
        TECClaim implementation = new TECClaim();
        IERC20[] memory redeemableTokens = new IERC20[](3);
        redeemableTokens[0] = IERC20(address(token1));
        redeemableTokens[1] = IERC20(address(token2));
        redeemableTokens[2] = IERC20(address(token3));
        
        bytes memory initData = abi.encodeWithSelector(
            TECClaim.initialize.selector,
            owner,
            IMiniMeToken(address(newSourceToken)),
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
        uint256 user1TecBalance = snapshotToken.balanceOf(user1);
        uint256 tecTotalSupply = snapshotToken.totalSupply();
        
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
        assertEq(snapshotToken.balanceOf(user1), 0);
        assertEq(snapshotToken.totalSupply(), tecTotalSupply - user1TecBalance);
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
        assertEq(snapshotToken.balanceOf(user1), 0);
        assertEq(snapshotToken.balanceOf(user2), 0);
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
        assertEq(snapshotToken.totalSupply(), 0);
        
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

        assertEq(snapshotToken.balanceOf(user1), 0);
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
        // Create a new source token for isolated test
        MockMiniMeToken newSourceTecToken = new MockMiniMeToken("TEC", "TEC", 1_000_000e18);
        
        // Create a new claim contract with only DAI
        TECClaim implementation = new TECClaim();
        IERC20[] memory redeemableTokens = new IERC20[](1);
        
        // Create new DAI for this test
        MockERC20 newDai = new MockERC20("DAI", "DAI", 50_000e18);
        redeemableTokens[0] = IERC20(address(newDai));

        bytes memory initData = abi.encodeWithSelector(
            TECClaim.initialize.selector,
            owner,
            IMiniMeToken(address(newSourceTecToken)),
            redeemableTokens,
            uint64(block.timestamp + CLAIM_DEADLINE)
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        TECClaim singleTokenClaim = TECClaim(address(proxy));
        
        // Get snapshot token created by the contract
        MockMiniMeTokenClone newSnapshotToken = MockMiniMeTokenClone(address(singleTokenClaim.token()));
        
        // Transfer DAI to claim contract
        newDai.transfer(address(singleTokenClaim), 50_000e18);

        // Activate the claim contract
        address[] memory emptyAddresses = new address[](0);
        singleTokenClaim.startClaim(emptyAddresses);

        // Give user some snapshot tokens (simulate snapshot with balance)
        address testUser = address(0x888);
        newSourceTecToken.copyBalanceToClone(address(newSnapshotToken), owner);
        newSnapshotToken.mint(testUser, 100_000e18);

        vm.prank(testUser);
        singleTokenClaim.claim();

        assertGt(newDai.balanceOf(testUser), 0);
        assertEq(newSnapshotToken.balanceOf(testUser), 0); // Snapshot tokens should be burned
    }

    function test_ProportionalDistributionAccuracy() public {
        uint256 user1TecBalance = snapshotToken.balanceOf(user1);
        uint256 tecTotalSupply = snapshotToken.totalSupply();
        
        uint256 expectedDai = (user1TecBalance * DAI_AMOUNT) / tecTotalSupply;
        uint256 expectedReth = (user1TecBalance * RETH_AMOUNT) / tecTotalSupply;

        vm.prank(user1);
        claim.claim();

        // Allow for rounding error of 1 wei
        assertApproxEqAbs(dai.balanceOf(user1), expectedDai, 1);
        assertApproxEqAbs(reth.balanceOf(user1), expectedReth, 1);
    }

    function test_ClaimEmitsCorrectEvent() public {
        uint256 user1Balance = snapshotToken.balanceOf(user1);

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
