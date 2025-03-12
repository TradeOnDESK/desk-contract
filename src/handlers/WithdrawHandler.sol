// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import {BaseHandler} from "./BaseHandler.sol";
import {IWETH} from "src/interfaces/tokens/IWETH.sol";
import {IAssetService} from "src/interfaces/services/IAssetService.sol";
import {IPerpService} from "src/interfaces/services/IPerpService.sol";
import {SafeCast} from "@openzeppelin/utils/math/SafeCast.sol";

contract WithdrawHandler is BaseHandler {
    using SafeCast for uint256;

    enum WithdrawAction {
        Process,
        Reject
    }

    address public assetService;
    address public perpService;

    mapping(uint256 => bool) public isProcessed;

    bool public isAllowPositiveUnsettled;

    event LogWithdrawProcessed(
        bytes32 indexed subaccount,
        address indexed tokenAddress,
        uint256 amount
    );
    event LogWithdrawRejected(
        bytes32 indexed subaccount,
        address indexed tokenAddress,
        uint256 amount
    );
    event LogSetAssetService(
        address indexed oldAssetService,
        address indexed newAssetService
    );
    event LogSetPerpService(
        address indexed oldPerpService,
        address indexed newPerpService
    );
    event LogSetIsAllowPositiveUnsettled(bool _prevFlag, bool _isAllow);

    error WithdrawHandler_InsufficientMargin();
    error WithdrawHandler_InsufficientCollateral();
    error WithdrawHandler_InvalidWithdrawalFee();

    function initialize(
        address _entrypoint,
        address _assetService,
        address _perpService
    ) external initializer {
        __initialize(_entrypoint);

        IPerpService(_perpService).BPS();
        IAssetService(_assetService).settlementToken();

        assetService = _assetService;
        perpService = _perpService;
    }

    function _executeAction(bytes memory _data) internal override {
        (
            uint256 _requestId,
            bytes32 _subaccount,
            uint256 _amount,
            address _tokenAddress,
            bytes32 _withdrawalFeeSubaccount,
            uint256 _withdrawalFee,
            WithdrawAction _action
        ) = abi.decode(
                _data,
                (
                    uint256,
                    bytes32,
                    uint256,
                    address,
                    bytes32,
                    uint256,
                    WithdrawAction
                )
            );
        if (_subaccount != bytes32(0) && !isProcessed[_requestId]) {
            if (_action == WithdrawAction.Process) {
                _processWithdraw(
                    _subaccount,
                    _amount,
                    _tokenAddress,
                    _withdrawalFeeSubaccount,
                    _withdrawalFee
                );
                emit LogWithdrawProcessed(_subaccount, _tokenAddress, _amount);
            } else {
                emit LogWithdrawRejected(_subaccount, _tokenAddress, _amount);
            }
            isProcessed[_requestId] = true;
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     ADMIN FUNCTIONS                     */
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

    function setIsAllowPositiveUnsettled(bool _isAllow) external onlyOwner {
        emit LogSetIsAllowPositiveUnsettled(isAllowPositiveUnsettled, _isAllow);
        isAllowPositiveUnsettled = _isAllow;
    }

    function getWithdrawableAmount(
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
            int256 _unsettled = _getSubaccountUnsettledE18(
                _assetService,
                _subaccount
            ) / int256(10 ** (18 - _decimals));
            if (_unsettled > 0 && isAllowPositiveUnsettled) {
                _subaccountTotalBalance += _unsettled;
            }
        }
        _amount = _subaccountTotalBalance > 0
            ? uint256(_subaccountTotalBalance)
            : uint256(0);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     INTERNAL FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _processWithdraw(
        bytes32 _subaccount,
        uint256 _amount,
        address _tokenAddress,
        bytes32 _withdrawalFeeSubaccount,
        uint256 _withdrawalFee
    ) internal {
        if (_withdrawalFee > _amount) {
            revert WithdrawHandler_InvalidWithdrawalFee();
        }

        if (getWithdrawableAmount(_subaccount, _tokenAddress) < _amount) {
            revert WithdrawHandler_InsufficientCollateral();
        }

        IAssetService _assetService = IAssetService(assetService);
        _assetService.adjustCollateral(
            _subaccount,
            _tokenAddress,
            -_amount.toInt256()
        );
        _assetService.adjustCollateral(
            _withdrawalFeeSubaccount,
            _tokenAddress,
            _withdrawalFee.toInt256()
        );

        _validateMMR(_assetService, _subaccount);
    }

    function _validateMMR(
        IAssetService _assetService,
        bytes32 _subaccount
    ) internal view {
        (uint256 _subaccountMMRE18, ) = IPerpService(perpService)
            .getSubAccountTotalMMRAndPositionSize(_subaccount);
        int256 _unsettledMargin = _getSubaccountUnsettledE18(
            _assetService,
            _subaccount
        );

        if (_unsettledMargin > 0) {
            _unsettledMargin =
                (_unsettledMargin *
                    _assetService
                        .collateralFactors(_assetService.settlementToken())
                        .toInt256()) /
                BPS.toInt256();
        }

        if (
            _assetService.getSubaccountTotalMargin(_subaccount) +
                _unsettledMargin <
            _subaccountMMRE18.toInt256()
        ) {
            revert WithdrawHandler_InsufficientMargin();
        }
    }

    function _getSubaccountUnsettledE18(
        IAssetService _assetService,
        bytes32 _subaccount
    ) internal view returns (int256 _unsettledE18) {
        address _perpService = perpService;
        (int256 _totalUPnLE18, int256 _totalFundingFeeE18) = IPerpService(
            _perpService
        ).getSubaccountTotalUnrealizedPNLAndFundingFee(_subaccount);
        int256 _borrowingFeeE18 = _assetService
            .getSubaccountPendingBorrowingFee(_subaccount);

        _unsettledE18 = _totalUPnLE18 - _totalFundingFeeE18 - _borrowingFeeE18;
    }

    receive() external payable {}
}
