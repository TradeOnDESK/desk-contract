// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import {BaseHandler} from "./BaseHandler.sol";

import {SafeCast} from "@openzeppelin/utils/math/SafeCast.sol";

import {IAssetService} from "src/interfaces/services/IAssetService.sol";
import {IPerpService} from "src/interfaces/services/IPerpService.sol";

contract SwapHandler is BaseHandler {
    using SafeCast for uint256;

    struct SwapAction {
        bytes32 srcSubaccount;
        bytes32 destSubaccount;
        bytes32 feeSubaccount;
        uint256 srcAmount;
        uint256 destAmount;
        uint256 feeAmount;
        address srcToken;
        address destToken;
        address feeToken;
    }

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

    error SwapHandler_InsufficientCollateral();
    error SwapHandler_InvalidToken();
    error SwapHandler_InvalidAmount();
    error SwapHandler_FeeSubaccountMustNotBeSrcSubaccount();

    function initialize(
        address _entryPoint,
        address _assetService,
        address _perpService
    ) external initializer {
        __initialize(_entryPoint);

        IAssetService(_assetService).BPS();
        IPerpService(_perpService).BPS();

        assetService = _assetService;
        perpService = _perpService;
    }

    function _executeAction(bytes memory _data) internal override {
        SwapAction memory _action = abi.decode(_data, (SwapAction));

        _validateAction(_action);

        IAssetService _assetService = IAssetService(assetService);

        _assetService.transferCollateral(
            _action.srcSubaccount,
            _action.destSubaccount,
            _action.srcToken,
            _action.srcAmount.toInt256()
        );
        _assetService.transferCollateral(
            _action.destSubaccount,
            _action.srcSubaccount,
            _action.destToken,
            _action.destAmount.toInt256()
        );

        if (_action.feeAmount > 0) {
            _assetService.transferCollateral(
                _action.srcSubaccount,
                _action.feeSubaccount,
                _action.feeToken,
                _action.feeAmount.toInt256()
            );
        }
    }

    function getAvailableAmount(
        bytes32 _subaccount,
        address _tokenAddress
    ) public view returns (uint256 _amount) {
        IAssetService _assetService = IAssetService(assetService);
        int256 _subaccountTotalBalance = _assetService.collaterals(
            _subaccount,
            _tokenAddress
        );
        address _settlementToken = _assetService.settlementToken();
        if (_tokenAddress == _settlementToken) {
            uint256 _decimals = _assetService.collateralTokenDecimals(
                _settlementToken
            );
            int256 _unsettled = _getSubaccountUnsettledE18(_subaccount) /
                int256(10 ** (18 - _decimals));
            if (_unsettled > 0) {
                _subaccountTotalBalance += _unsettled;
            }
        }
        _amount = _subaccountTotalBalance > 0
            ? uint256(_subaccountTotalBalance)
            : uint256(0);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ADMIN FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

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

    function _validateAction(SwapAction memory _action) internal view {
        IAssetService _assetService = IAssetService(assetService);
        if (_assetService.collateralFactors(_action.srcToken) == 0) {
            revert SwapHandler_InvalidToken();
        }
        if (_assetService.collateralFactors(_action.destToken) == 0) {
            revert SwapHandler_InvalidToken();
        }
        if (_assetService.collateralFactors(_action.feeToken) == 0) {
            revert SwapHandler_InvalidToken();
        }

        if (_action.srcToken == _action.destToken) {
            revert SwapHandler_InvalidToken();
        }

        if (_action.srcAmount == 0 || _action.destAmount == 0) {
            revert SwapHandler_InvalidAmount();
        }

        if (_action.feeSubaccount == _action.srcSubaccount) {
            revert SwapHandler_FeeSubaccountMustNotBeSrcSubaccount();
        }

        if (
            getAvailableAmount(_action.srcSubaccount, _action.srcToken) <
            _action.srcAmount
        ) {
            revert SwapHandler_InsufficientCollateral();
        }
    }

    function _getSubaccountUnsettledE18(
        bytes32 _subaccount
    ) internal view returns (int256 _unsettledE18) {
        IAssetService _assetService = IAssetService(assetService);
        address _perpService = perpService;
        (int256 _totalUPnLE18, int256 _totalFundingFeeE18) = IPerpService(
            _perpService
        ).getSubaccountTotalUnrealizedPNLAndFundingFee(_subaccount);
        int256 _borrowingFeeE18 = _assetService
            .getSubaccountPendingBorrowingFee(_subaccount);

        _unsettledE18 = _totalUPnLE18 - _totalFundingFeeE18 - _borrowingFeeE18;

        if (_unsettledE18 > 0) {
            _unsettledE18 =
                (_unsettledE18 *
                    _assetService
                        .collateralFactors(_assetService.settlementToken())
                        .toInt256()) /
                BPS.toInt256();
        }
    }
}
