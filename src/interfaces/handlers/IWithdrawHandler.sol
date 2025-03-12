// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import {IHandler} from "../IHandler.sol";

interface IWithdrawHandler is IHandler {
    function assetService() external view returns (address);

    function getWithdrawableAmount(
        bytes32 _subaccount,
        address _tokenAddress
    ) external view returns (uint256 _amount);
}
