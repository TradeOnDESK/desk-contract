// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import {IService} from "../IService.sol";

interface IOracleService is IService {
    error IOracleService_SlotsAreNotFullFilled();
    error IOracleService_LessThanMinSlotCountData();
    error IOracleService_InvalidPriceFeedId();

    event LogSetMarketPriceFeedId(uint32 indexed marketId, bytes32 priceFeedId);
    event LogSetTotalPriceCount(uint256 totalPriceCount);
    event LogSetWhitelisted(address indexed addr, bool isWhitelisted);

    function updatePrices(bytes32[] memory prices) external;

    function setPriceDecimals(uint256 priceFeedId, uint256 decimals) external;

    function setTotalSlotCount(uint256 totalSlotCount) external;

    function getPrice(
        uint256 priceFeedId
    ) external view returns (uint256 priceE18);

    function totalSlotCount() external view returns (uint256);

    function PRICES_PER_SLOT() external view returns (uint256);

    function encodePrices(
        uint256[] memory prices
    ) external view returns (bytes32[] memory);
}
