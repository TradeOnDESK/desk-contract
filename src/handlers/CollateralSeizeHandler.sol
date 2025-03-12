// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import {BaseHandler} from "./BaseHandler.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {IAssetService} from "src/interfaces/services/IAssetService.sol";
import {IPerpService} from "src/interfaces/services/IPerpService.sol";

contract CollateralSeizeHandler is BaseHandler {
    struct CollateralSeizeAction {
        bytes32 subaccount;
        address token;
        int256 amount;
        bytes32 insuranceFundSubaccount;
    }

    address public assetService;
    address public perpService;

    event LogCollateralSeized(
        bytes32 indexed subaccount,
        address indexed tokenAddress,
        int256 amount,
        bytes32 insuranceFundSubaccount
    );
    event LogSetAssetService(
        address indexed oldAssetService,
        address indexed newAssetService
    );
    event LogSetPerpService(
        address indexed oldPerpService,
        address indexed newPerpService
    );

    error CollateralSeizeHandler_IsNotLiquidating();
    error CollateralSeizeHandler_InsufficientCollateral();
    error CollateralSeizeHandler_InvalidAmount();
    error CollateralSeizeHandler_InvalidAddress();

    function initialize(
        address _entrypoint,
        address _assetService,
        address _perpService
    ) external initializer {
        __initialize(_entrypoint);

        IAssetService(_assetService).BPS();
        IPerpService(_perpService).BPS();

        assetService = _assetService;
        perpService = _perpService;
    }

    function setAssetService(address _assetService) external onlyOwner {
        IAssetService(_assetService).BPS();

        emit LogSetAssetService(assetService, _assetService);
        assetService = _assetService;
    }

    function setPerpService(address _perpService) external onlyOwner {
        IPerpService(_perpService).BPS();

        emit LogSetPerpService(perpService, _perpService);
        perpService = _perpService;
    }

    function _executeAction(bytes memory _data) internal override {
        IAssetService _assetService = IAssetService(assetService);

        CollateralSeizeAction memory _action = abi.decode(
            _data,
            (CollateralSeizeAction)
        );

        if (!IPerpService(perpService).isLiquidatings(_action.subaccount)) {
            revert CollateralSeizeHandler_IsNotLiquidating();
        }

        if (_action.token == _assetService.settlementToken()) {
            _assetService.settlePendingBorrowingFee(_action.subaccount);
            _assetService.settlePendingBorrowingFee(
                _action.insuranceFundSubaccount
            );
        }

        int256 _collatAmount = _assetService.collaterals(
            _action.subaccount,
            _action.token
        );

        if (
            (_collatAmount < 0 && _action.amount > 0) ||
            (_collatAmount > 0 && _action.amount < 0)
        ) {
            revert CollateralSeizeHandler_InvalidAmount();
        }

        if (_abs(_collatAmount) < _abs(_action.amount)) {
            revert CollateralSeizeHandler_InsufficientCollateral();
        }

        _assetService.transferCollateral(
            _action.subaccount,
            _action.insuranceFundSubaccount,
            _action.token,
            _action.amount
        );

        emit LogCollateralSeized(
            _action.subaccount,
            _action.token,
            _action.amount,
            _action.insuranceFundSubaccount
        );
    }

    function _abs(int256 _amount) internal pure returns (int256) {
        return _amount < 0 ? _amount * -1 : _amount;
    }
}
