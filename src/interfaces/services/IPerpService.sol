// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import {IService} from "../IService.sol";

interface IPerpService is IService {
    enum PositionSide {
        LONG,
        SHORT
    }

    struct Position {
        uint256 amountE18;
        uint256 avgEntryPriceE18;
        PositionSide side;
        int256 lastUpdatedFundingRateE18;
    }

    struct MarketInfo {
        string symbol;
        uint64 mmf;
        uint256 priceFeedId;
    }

    struct FundingAndPnL {
        int256 fundingE18;
        int256 pnlE18;
    }

    event LogSetMarketInfo(uint32 indexed marketId, MarketInfo marketInfo);
    event LogIncreaseCollateral(
        bytes32 indexed subaccount,
        address tokenAddress,
        uint256 amount
    );
    event LogApplyPosition(
        bytes32 indexed subaccount,
        uint32 indexed marketId,
        uint256 amountE18,
        uint256 avgEntryPriceE18,
        PositionSide side
    );

    event LogSetIsLiquidating(bytes32 indexed subaccount, bool isLiquidating);
    event LogSetAccumulativeFundingRate(
        uint32 indexed marketId,
        int256 accumulativeFundingRateE18
    );
    event LogUpdateAccumulativeFundingRate(
        uint32 indexed marketId,
        int256 accumulativeFundingRateE18
    );
    event LogSavePosition(
        bytes32 indexed subaccount,
        uint32 indexed marketId,
        Position newPosition
    );

    error PerpService_InvalidAddress();
    error PerpService_InvalidMarket();
    error PerpService_Unauthorized();

    function applyPosition(
        bytes32 subaccount,
        uint32 marketId,
        Position memory applyPosition
    ) external returns (FundingAndPnL memory);

    function setIsLiquidating(
        bytes32 _subAccountId,
        bool _isLiquidating
    ) external;

    function setMarketInfo(
        uint32 marketId,
        MarketInfo memory marketInfo
    ) external;

    function adjustAccumulativeFundingRate(
        uint32 marketId,
        int256 newFundingRateE18
    ) external;

    function isPositionExisted(
        bytes32 subaccount,
        uint32 marketId
    ) external view returns (bool);

    function markets(
        uint32 marketId
    )
        external
        view
        returns (string memory symbol, uint64 mmf, uint256 priceFeedId);

    function getMarket(
        uint32 marketId
    ) external view returns (MarketInfo memory);

    function getSubAccountTotalMMRAndPositionSize(
        bytes32 subaccount
    )
        external
        view
        returns (
            uint256 subaccountTotalMMRE18,
            uint256 subaccountTotalPositionSizeE18
        );

    function getSubaccountTotalUnrealizedPNLAndFundingFee(
        bytes32 subaccount
    ) external view returns (int256 totalUPNLE18, int256 totalFundingFeeE18);

    function getPositionPendingFundingFeePerMarket(
        bytes32 subaccount,
        uint32 marketId
    ) external view returns (int256 pendingFundingFeeE18);

    function getPosition(
        bytes32 subaccount,
        uint32 marketId
    ) external view returns (Position memory);

    function isLiquidatings(bytes32 subAccount) external view returns (bool);

    function getPositions(
        bytes32 subaccount
    ) external view returns (Position[] memory);

    function accumulativeFundingRate(
        uint32 marketId
    ) external view returns (int256 accumulativeFundingRateE18);

    function BPS() external view returns (uint256);
}
