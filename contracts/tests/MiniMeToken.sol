// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

/**
 * @title MiniMeToken
 * @author Simplified implementation for Solidity 0.8.28
 * @dev This is a simplified version of the original MiniMeToken by Jordi Baylina
 *      Adapted for modern Solidity and includes only the features needed for TEC shutdown
 */

interface ITokenController {
    function onTransfer(address _from, address _to, uint _amount) external returns(bool);
    function proxyPayment(address _owner) external payable returns(bool);
}

interface IMiniMeTokenFactory {
    function createCloneToken(
        address _parentToken,
        uint _snapshotBlock,
        string memory _tokenName,
        uint8 _decimalUnits,
        string memory _tokenSymbol,
        bool _transfersEnabled
    ) external returns (address);
}

/**
 * @dev MiniMeToken implementation with snapshot capabilities
 */
contract MiniMeToken {
    string public name;
    string public symbol;
    uint8 public decimals;
    
    address public controller;
    MiniMeToken public parentToken;
    uint public parentSnapshotBlock;
    uint public creationBlock;
    bool public transfersEnabled;
    IMiniMeTokenFactory public tokenFactory;
    
    // Checkpoint structure for tracking historical balances
    struct Checkpoint {
        uint128 fromBlock;
        uint128 value;
    }
    
    mapping(address => Checkpoint[]) private balances;
    Checkpoint[] private totalSupplyHistory;
    mapping(address => mapping(address => uint256)) private allowed;
    
    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);
    event ClaimedTokens(address indexed token, address indexed controller, uint balance);
    event NewCloneToken(address indexed cloneToken, uint snapshotBlock);
    
    modifier onlyController() {
        require(msg.sender == controller, "Only controller");
        _;
    }
    
    /**
     * @notice Constructor to create a MiniMeToken
     * @param _tokenFactory The factory used to create clone tokens
     * @param _parentToken Address of the parent token (0x0 for new token)
     * @param _parentSnapshotBlock Block number for snapshot (0 for new token)
     * @param _tokenName Name of the token
     * @param _decimalUnits Number of decimals
     * @param _tokenSymbol Token symbol
     * @param _transfersEnabled Whether transfers are enabled
     */
    constructor(
        IMiniMeTokenFactory _tokenFactory,
        MiniMeToken _parentToken,
        uint _parentSnapshotBlock,
        string memory _tokenName,
        uint8 _decimalUnits,
        string memory _tokenSymbol,
        bool _transfersEnabled
    ) {
        tokenFactory = _tokenFactory;
        name = _tokenName;
        decimals = _decimalUnits;
        symbol = _tokenSymbol;
        parentToken = _parentToken;
        parentSnapshotBlock = _parentSnapshotBlock;
        transfersEnabled = _transfersEnabled;
        creationBlock = block.number;
        controller = msg.sender;
    }
    
    /**
     * @notice Changes the controller of the contract
     * @param _newController The new controller address
     */
    function changeController(address _newController) external onlyController {
        controller = _newController;
    }
    
    /**
     * @notice Get balance of an account at current block
     * @param _owner The address to query
     * @return The balance
     */
    function balanceOf(address _owner) public view returns (uint256) {
        return balanceOfAt(_owner, block.number);
    }
    
    /**
     * @notice Get balance of an account at a specific block
     * @param _owner The address to query
     * @param _blockNumber The block number to query
     * @return The balance at the specified block
     */
    function balanceOfAt(address _owner, uint _blockNumber) public view returns (uint256) {
        // Check if there are any checkpoints for this address
        if (balances[_owner].length == 0) {
            // If no checkpoints and has parent, query parent at snapshot block
            if (address(parentToken) != address(0)) {
                return parentToken.balanceOfAt(_owner, parentSnapshotBlock);
            }
            return 0;
        }
        
        // Get value from checkpoints
        return getValueAt(balances[_owner], _blockNumber);
    }
    
    /**
     * @notice Get total supply at current block
     * @return The total supply
     */
    function totalSupply() public view returns (uint256) {
        return totalSupplyAt(block.number);
    }
    
    /**
     * @notice Get total supply at a specific block
     * @param _blockNumber The block number to query
     * @return The total supply at the specified block
     */
    function totalSupplyAt(uint _blockNumber) public view returns (uint256) {
        if (totalSupplyHistory.length == 0) {
            // If no history and has parent, query parent at snapshot block
            if (address(parentToken) != address(0)) {
                return parentToken.totalSupplyAt(parentSnapshotBlock);
            }
            return 0;
        }
        
        return getValueAt(totalSupplyHistory, _blockNumber);
    }
    
    /**
     * @notice Transfer tokens
     * @param _to Recipient address
     * @param _amount Amount to transfer
     * @return success
     */
    function transfer(address _to, uint256 _amount) public returns (bool) {
        require(transfersEnabled, "Transfers disabled");
        return doTransfer(msg.sender, _to, _amount);
    }
    
    /**
     * @notice Transfer tokens from one address to another
     * @param _from Source address
     * @param _to Recipient address
     * @param _amount Amount to transfer
     * @return success
     */
    function transferFrom(address _from, address _to, uint256 _amount) public returns (bool) {
        // Controller can move tokens freely
        if (msg.sender != controller) {
            require(transfersEnabled, "Transfers disabled");
            require(allowed[_from][msg.sender] >= _amount, "Insufficient allowance");
            allowed[_from][msg.sender] -= _amount;
        }
        return doTransfer(_from, _to, _amount);
    }
    
    /**
     * @notice Internal transfer function
     */
    function doTransfer(address _from, address _to, uint _amount) internal returns (bool) {
        if (_amount == 0) {
            emit Transfer(_from, _to, 0);
            return true;
        }
        
        require(block.number >= creationBlock, "Invalid block");
        require(_to != address(0), "Invalid recipient");
        require(_to != address(this), "Cannot transfer to token contract");
        
        uint256 previousBalanceFrom = balanceOfAt(_from, block.number);
        require(previousBalanceFrom >= _amount, "Insufficient balance");
        
        // Notify controller if it's a contract and has code
        if (controller != address(0) && isContract(controller)) {
            // Try to call onTransfer, but don't revert if the controller doesn't implement it
            try ITokenController(controller).onTransfer(_from, _to, _amount) returns (bool result) {
                require(result, "Controller rejected");
            } catch {
                // If controller doesn't implement onTransfer, allow transfer to proceed
            }
        }
        
        // Update balances
        updateValueAtNow(balances[_from], previousBalanceFrom - _amount);
        uint256 previousBalanceTo = balanceOfAt(_to, block.number);
        require(previousBalanceTo + _amount >= previousBalanceTo, "Overflow");
        updateValueAtNow(balances[_to], previousBalanceTo + _amount);
        
        emit Transfer(_from, _to, _amount);
        return true;
    }
    
    /**
     * @notice Approve spending
     * @param _spender Spender address
     * @param _amount Amount to approve
     * @return success
     */
    function approve(address _spender, uint256 _amount) public returns (bool) {
        require(transfersEnabled, "Transfers disabled");
        allowed[msg.sender][_spender] = _amount;
        emit Approval(msg.sender, _spender, _amount);
        return true;
    }
    
    /**
     * @notice Get allowance
     * @param _owner Owner address
     * @param _spender Spender address
     * @return The allowance
     */
    function allowance(address _owner, address _spender) public view returns (uint256) {
        return allowed[_owner][_spender];
    }
    
    /**
     * @notice Create a clone token at the current block
     * @param _cloneTokenName Name of clone token
     * @param _cloneDecimalUnits Decimals of clone token
     * @param _cloneTokenSymbol Symbol of clone token
     * @param _snapshotBlock Block number for snapshot (0 = current block - 1)
     * @param _transfersEnabled Whether transfers are enabled in clone
     * @return The new token contract
     */
    function createCloneToken(
        string memory _cloneTokenName,
        uint8 _cloneDecimalUnits,
        string memory _cloneTokenSymbol,
        uint _snapshotBlock,
        bool _transfersEnabled
    ) public returns (MiniMeToken) {
        uint256 snapshot = _snapshotBlock == 0 ? block.number - 1 : _snapshotBlock;
        
        address cloneToken = tokenFactory.createCloneToken(
            address(this),
            snapshot,
            _cloneTokenName,
            _cloneDecimalUnits,
            _cloneTokenSymbol,
            _transfersEnabled
        );
        
        MiniMeToken(payable(cloneToken)).changeController(msg.sender);
        
        emit NewCloneToken(cloneToken, snapshot);
        return MiniMeToken(payable(cloneToken));
    }
    
    /**
     * @notice Generate tokens (only controller)
     * @param _owner Address to receive tokens
     * @param _amount Amount to generate
     * @return success
     */
    function generateTokens(address _owner, uint _amount) external onlyController returns (bool) {
        uint curTotalSupply = totalSupply();
        require(curTotalSupply + _amount >= curTotalSupply, "Overflow");
        
        uint previousBalanceTo = balanceOf(_owner);
        require(previousBalanceTo + _amount >= previousBalanceTo, "Overflow");
        
        updateValueAtNow(totalSupplyHistory, curTotalSupply + _amount);
        updateValueAtNow(balances[_owner], previousBalanceTo + _amount);
        
        emit Transfer(address(0), _owner, _amount);
        return true;
    }
    
    /**
     * @notice Destroy tokens (only controller)
     * @param _owner Address to burn tokens from
     * @param _amount Amount to burn
     * @return success
     */
    function destroyTokens(address _owner, uint _amount) external onlyController returns (bool) {
        uint curTotalSupply = totalSupply();
        require(curTotalSupply >= _amount, "Not enough supply");
        
        uint previousBalanceFrom = balanceOf(_owner);
        require(previousBalanceFrom >= _amount, "Insufficient balance");
        
        updateValueAtNow(totalSupplyHistory, curTotalSupply - _amount);
        updateValueAtNow(balances[_owner], previousBalanceFrom - _amount);
        
        emit Transfer(_owner, address(0), _amount);
        return true;
    }
    
    /**
     * @notice Enable or disable transfers (only controller)
     * @param _transfersEnabled New transfers enabled state
     */
    function enableTransfers(bool _transfersEnabled) external onlyController {
        transfersEnabled = _transfersEnabled;
    }
    
    /**
     * @notice Claim tokens sent to this contract (only controller)
     * @param _token Token address (0x0 for ETH)
     */
    function claimTokens(address _token) external onlyController {
        if (_token == address(0)) {
            payable(controller).transfer(address(this).balance);
            return;
        }
        
        MiniMeToken token = MiniMeToken(payable(_token));
        uint balance = token.balanceOf(address(this));
        token.transfer(controller, balance);
        emit ClaimedTokens(_token, controller, balance);
    }
    
    /**
     * @dev Get value at a specific block from checkpoints
     */
    function getValueAt(Checkpoint[] storage checkpoints, uint _block) internal view returns (uint) {
        if (checkpoints.length == 0) {
            return 0;
        }
        
        // Shortcut for the actual value
        if (_block >= checkpoints[checkpoints.length - 1].fromBlock) {
            return checkpoints[checkpoints.length - 1].value;
        }
        if (_block < checkpoints[0].fromBlock) {
            return 0;
        }
        
        // Binary search
        uint minIndex = 0;
        uint maxIndex = checkpoints.length - 1;
        while (maxIndex > minIndex) {
            uint mid = (maxIndex + minIndex + 1) / 2;
            if (checkpoints[mid].fromBlock <= _block) {
                minIndex = mid;
            } else {
                maxIndex = mid - 1;
            }
        }
        return checkpoints[minIndex].value;
    }
    
    /**
     * @dev Update value at current block
     */
    function updateValueAtNow(Checkpoint[] storage checkpoints, uint _value) internal {
        require(_value <= type(uint128).max, "Value too large");
        
        if (checkpoints.length == 0 || checkpoints[checkpoints.length - 1].fromBlock < block.number) {
            checkpoints.push(Checkpoint({
                fromBlock: uint128(block.number),
                value: uint128(_value)
            }));
        } else {
            checkpoints[checkpoints.length - 1].value = uint128(_value);
        }
    }
    
    /**
     * @dev Check if address is a contract
     */
    function isContract(address _addr) internal view returns (bool) {
        if (_addr == address(0)) return false;
        uint size;
        assembly {
            size := extcodesize(_addr)
        }
        return size > 0;
    }
    
    /**
     * @dev Return minimum of two uints
     */
    function min(uint a, uint b) internal pure returns (uint) {
        return a < b ? a : b;
    }
    
    /**
     * @notice Fallback function
     */
    receive() external payable {
        require(isContract(controller), "Controller not set");
        require(ITokenController(controller).proxyPayment{value: msg.value}(msg.sender), "Payment rejected");
    }
}

/**
 * @title MiniMeTokenFactory
 * @dev Factory contract to create MiniMeToken clones
 */
contract MiniMeTokenFactory is IMiniMeTokenFactory {
    event NewCloneToken(address indexed cloneToken, address indexed parentToken, uint snapshotBlock);
    
    /**
     * @notice Create a clone token
     * @param _parentToken Address of the parent token
     * @param _snapshotBlock Block number for snapshot
     * @param _tokenName Name of the new token
     * @param _decimalUnits Number of decimals
     * @param _tokenSymbol Token symbol
     * @param _transfersEnabled Whether transfers are enabled
     * @return The address of the new token
     */
    function createCloneToken(
        address _parentToken,
        uint _snapshotBlock,
        string memory _tokenName,
        uint8 _decimalUnits,
        string memory _tokenSymbol,
        bool _transfersEnabled
    ) external returns (address) {
        MiniMeToken newToken = new MiniMeToken(
            this,
            MiniMeToken(payable(_parentToken)),
            _snapshotBlock,
            _tokenName,
            _decimalUnits,
            _tokenSymbol,
            _transfersEnabled
        );
        
        newToken.changeController(msg.sender);
        emit NewCloneToken(address(newToken), _parentToken, _snapshotBlock);
        return address(newToken);
    }
}


