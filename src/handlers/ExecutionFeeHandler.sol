// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import {BaseHandler} from "./BaseHandler.sol";

import {IAssetService} from "src/interfaces/services/IAssetService.sol";

contract ExecutionFeeHandler is BaseHandler {
    uint256 public constant MAX_EXECUTION_FEE = 1e10;
    address public assetService;

    event LogSetAssetService(
        address indexed oldAssetService,
        address indexed newAssetService
    );

    error ExecutionFeeHandler_FeeExceedsMax();

    function initialize(
        address _entryPoint,
        address _assetService
    ) external initializer {
        __initialize(_entryPoint);

        IAssetService(_assetService).BPS();

        assetService = _assetService;
    }

    function setAssetService(address _assetService) external onlyOwner {
        IAssetService(_assetService).BPS();

        emit LogSetAssetService(assetService, _assetService);
        assetService = _assetService;
    }

    function _executeAction(bytes memory _data) internal override {
        (
            bytes32 _subaccount,
            uint256 _totalExecutionFee,
            bytes32 _protocolFeeSubaccount
        ) = abi.decode(_data, (bytes32, uint256, bytes32));
        if (_totalExecutionFee > MAX_EXECUTION_FEE) {
            revert ExecutionFeeHandler_FeeExceedsMax();
        }

        IAssetService _assetService = IAssetService(assetService);
        _assetService.transferCollateral(
            _subaccount,
            _protocolFeeSubaccount,
            _assetService.settlementToken(),
            int256(_totalExecutionFee)
        );
    }
}
