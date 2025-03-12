// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import {BaseHandler} from "./BaseHandler.sol";
import {IAssetService} from "src/interfaces/services/IAssetService.sol";
import {IPerpService} from "src/interfaces/services/IPerpService.sol";
import {SafeCast} from "@openzeppelin/utils/math/SafeCast.sol";

contract LiquidationHandler is BaseHandler {
    using SafeCast for uint256;

    struct LiquidateAction {
        bytes32 subaccount;
        bytes32 insuranceFundSubaccount;
        uint256 liquidationFee;
        bool isLiquidating;
    }

    uint256 public constant MAX_LIQUIDATION_FEE_BPS = 1000;

    address public assetService;
    address public perpService;

    event LogSetAssetService(
        address indexed oldAssetService,
        address indexed newAssetService
    );
    event LogSetPerpService(
        address indexed oldPerpService,
        address indexed newPerpService
    );

    error LiquidationHandler_BelowMMR();
    error LiquidationHandler_AboveMMR();
    error LiquidationHandler_ExcessiveLiquidationFee();

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
        LiquidateAction memory _action = abi.decode(_data, (LiquidateAction));

        IPerpService _perpService = IPerpService(perpService);
        IAssetService _assetService = IAssetService(assetService);
        address _settlementToken = _assetService.settlementToken();

        int256 _totalMarginWithUnsettledE18;
        {
            int256 _borrowingFeeE18 = _assetService
                .getSubaccountPendingBorrowingFee(_action.subaccount);
            (int256 _totalUPnLE18, int256 _totalFundingFeeE18) = _perpService
                .getSubaccountTotalUnrealizedPNLAndFundingFee(
                    _action.subaccount
                );

            int256 _unsettledE18 = _totalUPnLE18 -
                _totalFundingFeeE18 -
                _borrowingFeeE18;

            if (_unsettledE18 > 0) {
                _unsettledE18 =
                    (_unsettledE18 *
                        _assetService
                            .collateralFactors(_settlementToken)
                            .toInt256()) /
                    int256(BPS);
            }

            _totalMarginWithUnsettledE18 =
                _assetService.getSubaccountTotalMargin(_action.subaccount) +
                _unsettledE18;
        }

        (
            uint256 _subaccountMMRE18,
            uint256 _subaccountTotalPositionSizeE18
        ) = _perpService.getSubAccountTotalMMRAndPositionSize(
                _action.subaccount
            );

        if (_action.isLiquidating) {
            if (_totalMarginWithUnsettledE18 >= _subaccountMMRE18.toInt256()) {
                revert LiquidationHandler_AboveMMR();
            }
            uint256 decimals = _assetService.collateralTokenDecimals(
                _settlementToken
            );
            if (
                _action.liquidationFee * (10 ** (18 - decimals)) >
                (_subaccountTotalPositionSizeE18 * MAX_LIQUIDATION_FEE_BPS) /
                    BPS
            ) {
                revert LiquidationHandler_ExcessiveLiquidationFee();
            }
            if (_action.liquidationFee > 0) {
                _assetService.transferCollateral(
                    _action.subaccount,
                    _action.insuranceFundSubaccount,
                    _settlementToken,
                    _action.liquidationFee.toInt256()
                );
            }
        } else {
            if (_totalMarginWithUnsettledE18 < _subaccountMMRE18.toInt256()) {
                revert LiquidationHandler_BelowMMR();
            }
        }

        _perpService.setIsLiquidating(
            _action.subaccount,
            _action.isLiquidating
        );
    }
}
