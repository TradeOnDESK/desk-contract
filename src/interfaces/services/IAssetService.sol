// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {IEntrypoint} from "../IEntrypoint.sol";
import {IService} from "../IService.sol";

interface IAssetService is IService {
    struct BorrowingAndLendingInfo {
        uint128 borrowingRateE18;
        uint128 lendingRateE18;
    }

    event LogAdjustCollateral(
        bytes32 indexed subaccount,
        address indexed tokenAddress,
        int256 adjustAmount
    );
    event LogSetCollateralFactor(address tokenAddress, uint256 factor);
    event LogSetAssetPriceId(address tokenAddress, uint256 priceFeedId);
    event LogSetProtocolBorrowingFeeBPS(uint256 oldBPS, uint256 newBPS);
    event LogSetOracle(address oracle);
    event LogSetSettlementToken(address indexed settlementToken);
    event LogSetCollateralTokenDecimals(
        address indexed tokenAddress,
        uint8 decimals
    );
    event LogTransferCollateral(
        bytes32 indexed subaccountFrom,
        bytes32 indexed subaccountTo,
        address tokenAddress,
        int256 amount
    );
    event LogBorrowingAndLendingRateAccumulated(
        uint128 borrowingRateE18,
        uint128 lendingRateE18
    );
    event LogSubaccountReceiveLendingFee(
        bytes32 indexed subaccount,
        uint256 lendingFee
    );
    event LogSubaccountPayBorrowingFee(
        bytes32 indexed subaccount,
        uint256 borrowingFee
    );

    error AssetService_InvalidAddress();
    error AssetService_InvalidAmount();
    error AssetService_InsufficientCollateral();
    error AssetService_InvalidCollateralFactor();

    function adjustCollateral(
        bytes32 subaccount,
        address tokenAddress,
        int256 adjustAmount
    ) external;

    function setSettlementToken(address settlementToken) external;

    function setAssetPriceId(
        address tokenAddress,
        uint256 priceFeedId
    ) external;

    function setCollateralFactor(address tokenAddress, uint256 factor) external;

    function transferCollateral(
        bytes32 subaccountFrom,
        bytes32 subaccountTo,
        address tokenAddress,
        int256 amount
    ) external;

    function accumulateBorrowingAndLendingRate(
        uint120 borrowingRateE18,
        uint120 lendingRateE18
    ) external;

    function settlePendingBorrowingFee(bytes32 subaccount) external;

    function collaterals(
        bytes32 subaccount,
        address tokenAddress
    ) external view returns (int256);

    function getSubaccountTotalMargin(
        bytes32 subaccount
    ) external view returns (int256);

    function collateralFactors(address token) external view returns (uint256);

    function getAssetPrice(
        address tokenAddress
    ) external view returns (uint256);

    function getCurrentProtocolBorrowingAndLendingInfo()
        external
        view
        returns (IAssetService.BorrowingAndLendingInfo memory curentInfo);

    function getSubaccountPendingBorrowingFee(
        bytes32 subaccount
    ) external view returns (int256 borrowingFeeDebtE18);

    function getSubaccountCollateralList(
        bytes32 _subaccount
    ) external view returns (address[] memory _subaccountCollateralLists);

    function BPS() external view returns (uint256);

    function settlementToken() external view returns (address);

    function accumulativeBorrowingRateE18() external view returns (uint120);

    function accumulativeLendingRateE18() external view returns (uint120);

    function collateralTokenDecimals(
        address tokenAddress
    ) external view returns (uint8);
}
