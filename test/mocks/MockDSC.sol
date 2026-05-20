// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { ERC20Burnable, ERC20 } from "openzeppelin/token/ERC20/extensions/ERC20Burnable.sol";
import { Ownable } from "openzeppelin/access/Ownable.sol";
import { MockV3Aggregator } from "chainlink/tests/MockV3Aggregator.sol";

contract MockDSC is ERC20Burnable, Ownable {
    error DecentralizedStableCoin__AmountMustBeMoreThanZero();
    error DecentralizedStableCoin__BurnAmountExceedsBalance();
    error DecentralizedStableCoin__NotZeroAddress();

    constructor(address initialOwner) ERC20("DecentralizedStableCoin", "DSC") Ownable(initialOwner) { }

    function burn(uint256 _amount) public virtual override onlyOwner {
        if (_amount <= 0) {
            revert DecentralizedStableCoin__AmountMustBeMoreThanZero();
        }
        if (balanceOf(msg.sender) < _amount) {
            revert DecentralizedStableCoin__BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) public virtual onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralizedStableCoin__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert DecentralizedStableCoin__AmountMustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}

contract MockDSCFailedMint is MockDSC {
    constructor(address initialOwner) MockDSC(initialOwner) { }

    function mint(address _to, uint256 _amount) public override onlyOwner returns (bool) {
        super.mint(_to, _amount);
        return false;
    }
}

contract MockDSCFailedTransfer is MockDSC {
    constructor(address initialOwner) MockDSC(initialOwner) { }

    function transfer(
        address,
        /*recipient*/
        uint256 /*amount*/
    )
        public
        pure
        override
        returns (bool)
    {
        return false;
    }
}

contract MockDSCFailedTransferFrom is MockDSC {
    constructor(address initialOwner) MockDSC(initialOwner) { }

    function transferFrom(
        address, /*sender*/
        address, /*recipient*/
        uint256 /*amount*/
    )
        public
        pure
        override
        returns (bool)
    {
        return false;
    }
}

contract MockDSCCrashPriceDuringBurn is MockDSC {
    address mockAggregator;

    constructor(address _mockAggregator, address initialOwner) MockDSC(initialOwner) {
        mockAggregator = _mockAggregator;
    }

    function burn(uint256 _amount) public virtual override onlyOwner {
        MockV3Aggregator(mockAggregator).updateAnswer(0);
        super.burn(_amount);
    }
}
