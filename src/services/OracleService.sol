// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import {BaseService} from "./BaseService.sol";

import {IOracleService} from "src/interfaces/services/IOracleService.sol";

contract OracleService is BaseService, IOracleService {
    uint256 public constant PRICES_PER_SLOT = 8;

    uint256 public totalSlotCount;

    bytes32[] public prices;
    mapping(uint256 priceFeedId => uint256 divisorExpo) public priceDecimals;

    function initialize() external initializer {
        __initialize();
    }

    function updatePrices(bytes32[] calldata _prices) external onlyWhitelisted {
        if (_prices.length < totalSlotCount)
            revert IOracleService_LessThanMinSlotCountData();
        prices = _prices;
    }

    function setPriceDecimals(
        uint256 _priceFeedId,
        uint256 _decimals
    ) external onlyMaintainer {
        _ensureValidPriceFeedId(_priceFeedId);
        priceDecimals[_priceFeedId] = _decimals;
    }

    function setTotalSlotCount(
        uint256 _totalSlotCount
    ) external onlyMaintainer {
        totalSlotCount = _totalSlotCount;
        emit LogSetTotalPriceCount(_totalSlotCount);
    }

    function encodePrices(
        uint256[] memory _prices
    ) external pure returns (bytes32[] memory) {
        if (_prices.length % PRICES_PER_SLOT != 0)
            revert IOracleService_SlotsAreNotFullFilled();
        bytes32[] memory encodedPrices = new bytes32[](
            _prices.length / PRICES_PER_SLOT
        );

        uint256 _slotIndex = 0;
        uint256 _length = _prices.length;
        for (; _slotIndex < _length; ) {
            bytes32 _packedPrices;
            uint256 _priceIndexWithinSlot = 0;
            for (; _priceIndexWithinSlot < PRICES_PER_SLOT; ) {
                _packedPrices |= (bytes32(
                    uint256(_prices[_slotIndex + _priceIndexWithinSlot])
                ) << (256 - (_priceIndexWithinSlot + 1) * 32));
                unchecked {
                    _priceIndexWithinSlot++;
                }
            }
            encodedPrices[_slotIndex / PRICES_PER_SLOT] = _packedPrices;
            unchecked {
                _slotIndex += PRICES_PER_SLOT;
            }
        }
        return encodedPrices;
    }

    function getPrice(
        uint256 _priceFeedId
    ) external view override returns (uint256 _priceE18) {
        _ensureValidPriceFeedId(_priceFeedId);

        uint256 _slotIndex = _priceFeedId / PRICES_PER_SLOT;
        uint256 _slotOffset = _priceFeedId % PRICES_PER_SLOT;
        bytes32 _pricesSlot = prices[_slotIndex];

        _priceE18 = uint32(
            uint256((_pricesSlot >> (256 - (32 * (_slotOffset + 1)))))
        );
        _priceE18 *= 10 ** (priceDecimals[_priceFeedId]);
    }

    function _ensureValidPriceFeedId(uint256 _priceFeedId) internal view {
        if (_priceFeedId > (totalSlotCount * PRICES_PER_SLOT) - 1)
            revert IOracleService_InvalidPriceFeedId();
    }
}
