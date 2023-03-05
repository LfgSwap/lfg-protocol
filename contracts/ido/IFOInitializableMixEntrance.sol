// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "./IFOInitializableMix.sol";

/**
 * @title IFOInitializableV7 withdraw nft check
 */
contract IFOInitializableMixEntrance is IFOInitializableMix {
    
    constructor() public {
    }

    //@dev transferAssets out side
    function depositPool(uint256 amount, address referral) external payable {

        beforeDeposit(msg.sender, amount);
        
        // pay assets
        raiseTokenSafeTransferFrom(msg.sender, address(this), amount);

        
        _depositPool(msg.sender, referral, amount);
    }

    function beforeHarvest(address user) internal virtual override {
    }

    function beforeDeposit(address user, uint256 amount) internal virtual override {
    }

}