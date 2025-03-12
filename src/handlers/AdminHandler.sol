// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import {BaseHandler} from "./BaseHandler.sol";

import {IOracleService} from "src/interfaces/services/IOracleService.sol";
import {IPerpService} from "src/interfaces/services/IPerpService.sol";
import {IAssetService} from "src/interfaces/services/IAssetService.sol";

contract AdminHandler is BaseHandler {
    enum AdminAction {
        UpdateFundingRate,
        UpdatePrices,
        UpdateBorrowingAndLendingRate
    }

    address public oracleService;
    address public perpService;
    address public assetService;

    error AdminHandler_InvalidAction();

    event LogSetOracleService(
        address indexed oldOracleService,
        address indexed newOracleService
    );
    event LogSetAssetService(
        address indexed oldAssetService,
        address indexed newAssetService
    );
    event LogSetPerpService(
        address indexed oldPerpService,
        address indexed newPerpService
    );

    function initialize(
        address _entryPoint,
        address _oracleService,
        address _perpService,
        address _assetService
    ) external initializer {
        __initialize(_entryPoint);

        IOracleService(_oracleService).PRICES_PER_SLOT();
        IPerpService(_perpService).BPS();
        IAssetService(_assetService).BPS();

        oracleService = _oracleService;
        perpService = _perpService;
        assetService = _assetService;
    }

    function _executeAction(bytes memory _data) internal override {
        (AdminAction _action, bytes memory _payload) = abi.decode(
            _data,
            (AdminAction, bytes)
        );
        if (_action == AdminAction.UpdatePrices) {
            _updatePrices(_payload);
        } else if (_action == AdminAction.UpdateFundingRate) {
            _updateFundingRate(_payload);
        } else if (_action == AdminAction.UpdateBorrowingAndLendingRate) {
            _updateBorrowingAndLendingRate(_payload);
        } else {
            revert AdminHandler_InvalidAction();
        }
    }

    function setOracleService(address _oracleService) external onlyOwner {
        IOracleService(_oracleService).PRICES_PER_SLOT();

        emit LogSetOracleService(oracleService, _oracleService);
        oracleService = _oracleService;
    }

    function setPerpService(address _perpService) external onlyOwner {
        IPerpService(_perpService).BPS();

        emit LogSetPerpService(perpService, _perpService);
        perpService = _perpService;
    }

    function setAssetService(address _assetService) external onlyOwner {
        IAssetService(_assetService).BPS();

        emit LogSetAssetService(assetService, _assetService);
        assetService = _assetService;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     INTERNAL FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _updatePrices(bytes memory _payload) internal {
        bytes32[] memory prices = abi.decode(_payload, (bytes32[]));
        IOracleService(oracleService).updatePrices(prices);
    }

    function _updateFundingRate(bytes memory _payload) internal {
        (uint32 _marketId, int256 _fundingRate) = abi.decode(
            _payload,
            (uint32, int256)
        );
        IPerpService(perpService).adjustAccumulativeFundingRate(
            _marketId,
            _fundingRate
        );
    }

    function _updateBorrowingAndLendingRate(bytes memory _payload) internal {
        (uint120 _borrowingRate, uint120 _lendingRate) = abi.decode(
            _payload,
            (uint120, uint120)
        );
        IAssetService(assetService).accumulateBorrowingAndLendingRate(
            _borrowingRate,
            _lendingRate
        );
    }
}
