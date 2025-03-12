// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import {BaseService} from "./BaseService.sol";
import {IPerpService} from "src/interfaces/services/IPerpService.sol";
import {IOracleService} from "src/interfaces/services/IOracleService.sol";
import {EnumerableSet} from "@openzeppelin/utils/structs/EnumerableSet.sol";
import {SafeCast} from "@openzeppelin/utils/math/SafeCast.sol";

contract PerpService is BaseService, IPerpService {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;
    using SafeCast for uint256;

    uint256 public constant BPS = 1e4;

    address public oracleService;

    mapping(uint32 => int256) public accumulativeFundingRate;
    mapping(uint32 => MarketInfo) public markets;
    mapping(bytes32 => mapping(uint32 => Position)) public positions;
    mapping(bytes32 => bool) public isLiquidatings;
    mapping(bytes32 => EnumerableSet.UintSet)
        private _subaccountActivePositions;

    function initialize(address _oracleService) external initializer {
        __initialize();

        IOracleService(_oracleService).PRICES_PER_SLOT();

        oracleService = _oracleService;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      ONLY WHITELISTED                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function applyPosition(
        bytes32 _subaccount,
        uint32 _marketId,
        Position memory _applyPosition
    ) external onlyWhitelisted returns (FundingAndPnL memory) {
        Position memory _oldPosition = positions[_subaccount][_marketId];
        Position memory _newPosition;
        FundingAndPnL memory _net = FundingAndPnL({fundingE18: 0, pnlE18: 0});
        int256 _accumulativeFundingRate = accumulativeFundingRate[_marketId];

        if (
            _oldPosition.amountE18 != 0 &&
            _subaccountActivePositions[_subaccount].contains(_marketId)
        ) {
            _net.fundingE18 = _calculatePendingFundingFee(
                _oldPosition,
                _accumulativeFundingRate
            );
            _net.pnlE18 = _calculateRealizePnl(_oldPosition, _applyPosition);
            _newPosition = _mergePositionAndUpdateAccumFundingRate(
                _oldPosition,
                _applyPosition,
                _marketId
            );
        } else {
            _newPosition = _applyPosition;
            _newPosition.lastUpdatedFundingRateE18 = _accumulativeFundingRate;
        }
        _savePosition(_subaccount, _marketId, _newPosition);

        return _net;
    }

    function setIsLiquidating(
        bytes32 _subaccount,
        bool _isLiquidating
    ) external onlyWhitelisted {
        isLiquidatings[_subaccount] = _isLiquidating;
        emit LogSetIsLiquidating(_subaccount, _isLiquidating);
    }

    function adjustAccumulativeFundingRate(
        uint32 _marketId,
        int256 _newFundingRateE18
    ) external onlyWhitelisted {
        accumulativeFundingRate[_marketId] += _newFundingRateE18;
        emit LogUpdateAccumulativeFundingRate(
            _marketId,
            accumulativeFundingRate[_marketId]
        );
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         Init Setter Functions              */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    struct SetPosition {
        bytes32 subaccount;
        uint32 marketId;
        Position newPosition;
    }

    function initSetPositions(SetPosition[] calldata _data) external onlyOwner {
        uint256 _len = _data.length;
        uint256 _i = 0;
        for (; _i < _len; ) {
            _initSetPosition(
                _data[_i].subaccount,
                _data[_i].marketId,
                _data[_i].newPosition
            );
            unchecked {
                ++_i;
            }
        }
    }

    function _initSetPosition(
        bytes32 _subaccount,
        uint32 _marketId,
        Position calldata _newPosition
    ) internal onlyOwner {
        positions[_subaccount][_marketId] = _newPosition;
        _subaccountActivePositions[_subaccount].add(_marketId);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         ONLY MAINTAINER                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function setMarketInfo(
        uint32 _marketId,
        MarketInfo memory _marketInfo
    ) external onlyMaintainer {
        markets[_marketId] = _marketInfo;
        emit LogSetMarketInfo(_marketId, _marketInfo);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         ONLY OWNER                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function setAccumulativeFundingRate(
        uint32 _marketId,
        int256 _newAccumulativeFundingRateE18
    ) external onlyOwner {
        accumulativeFundingRate[_marketId] = _newAccumulativeFundingRateE18;
        emit LogSetAccumulativeFundingRate(
            _marketId,
            _newAccumulativeFundingRateE18
        );
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function getPositionPendingFundingFeePerMarket(
        bytes32 _subaccount,
        uint32 _marketId
    ) external view returns (int256) {
        Position memory _position = positions[_subaccount][_marketId];
        return
            _calculatePendingFundingFee(
                _position,
                accumulativeFundingRate[_marketId]
            );
    }

    function getPosition(
        bytes32 _subaccount,
        uint32 _marketId
    ) external view returns (Position memory) {
        return positions[_subaccount][_marketId];
    }

    function getPositions(
        bytes32 _subaccount
    ) external view returns (Position[] memory) {
        return _getPositions(_subaccount);
    }

    function isPositionExisted(
        bytes32 _subaccount,
        uint32 _marketId
    ) external view returns (bool) {
        return _subaccountActivePositions[_subaccount].contains(_marketId);
    }

    function getSubAccountTotalMMRAndPositionSize(
        bytes32 _subaccount
    )
        external
        view
        returns (uint256 _totalMMRE18, uint256 _totalPositionSizeE18)
    {
        IOracleService _oracleService = IOracleService(oracleService);
        uint256 _length = _subaccountActivePositions[_subaccount].length();
        if (_length == 0) {
            return (0, 0);
        }

        uint256 _i;
        uint32 _marketId;
        uint256 _markPriceE18;
        for (; _i < _length; ) {
            _marketId = uint32(_subaccountActivePositions[_subaccount].at(_i));
            Position memory _position = positions[_subaccount][_marketId];
            _markPriceE18 = _oracleService.getPrice(
                markets[_marketId].priceFeedId
            );

            _totalMMRE18 =
                _totalMMRE18 +
                ((_position.amountE18 *
                    _position.avgEntryPriceE18 *
                    markets[_marketId].mmf) /
                    1e18 /
                    BPS);
            _totalPositionSizeE18 =
                _totalPositionSizeE18 +
                ((_position.amountE18 * _markPriceE18) / 1e18);

            unchecked {
                ++_i;
            }
        }
    }

    function getSubaccountTotalUnrealizedPNLAndFundingFee(
        bytes32 _subaccount
    ) external view returns (int256 _totalUPNLE18, int256 _totalFundingFeeE18) {
        uint256 _length = _subaccountActivePositions[_subaccount].length();
        if (_length == 0) {
            return (0, 0);
        }

        uint256 _i;
        int256 _positionUPNLE18;
        int256 _positionFundingFeeE18;
        uint32 _marketId;
        Position memory _position;
        for (; _i < _length; ++_i) {
            _marketId = uint32(_subaccountActivePositions[_subaccount].at(_i));
            _position = positions[_subaccount][_marketId];

            _positionUPNLE18 = _calculatePositionUPNL(_position, _marketId);
            _positionFundingFeeE18 = _calculatePendingFundingFee(
                _position,
                accumulativeFundingRate[_marketId]
            );

            _totalUPNLE18 += _positionUPNLE18;
            _totalFundingFeeE18 += _positionFundingFeeE18;
        }
    }

    function getMarket(
        uint32 _marketId
    ) external view returns (MarketInfo memory) {
        return markets[_marketId];
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     INTERNAL FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _savePosition(
        bytes32 _subaccount,
        uint32 _marketId,
        Position memory _newPosition
    ) internal {
        if (!_subaccountActivePositions[_subaccount].contains(_marketId)) {
            _subaccountActivePositions[_subaccount].add(_marketId);
        }
        if (_newPosition.amountE18 == 0) {
            _subaccountActivePositions[_subaccount].remove(_marketId);
        }
        positions[_subaccount][_marketId] = _newPosition;
        emit LogSavePosition(_subaccount, _marketId, _newPosition);
    }

    function _getPositions(
        bytes32 _subaccount
    ) internal view returns (Position[] memory) {
        uint256 _i;
        uint256 _length = _subaccountActivePositions[_subaccount].length();
        Position[] memory _positions = new Position[](_length);
        for (; _i < _length; ) {
            uint32 _marketId = uint32(
                _subaccountActivePositions[_subaccount].at(_i)
            );
            _positions[_i] = positions[_subaccount][_marketId];

            unchecked {
                ++_i;
            }
        }
        return _positions;
    }

    function _calculatePositionUPNL(
        Position memory _position,
        uint32 _marketId
    ) internal view returns (int256) {
        uint256 _markPriceE18 = IOracleService(oracleService).getPrice(
            markets[_marketId].priceFeedId
        );

        int256 _priceDiffE18;
        if (_position.side == PositionSide.LONG) {
            _priceDiffE18 =
                _markPriceE18.toInt256() -
                _position.avgEntryPriceE18.toInt256();
        } else {
            _priceDiffE18 =
                _position.avgEntryPriceE18.toInt256() -
                _markPriceE18.toInt256();
        }
        return (_position.amountE18.toInt256() * _priceDiffE18) / 1e18;
    }

    function _mergePositionAndUpdateAccumFundingRate(
        Position memory _currentPosition,
        Position memory _applyPosition,
        uint32 _marketId
    ) internal view onlyWhitelisted returns (Position memory) {
        if (_currentPosition.side == _applyPosition.side) {
            _applyPosition.avgEntryPriceE18 =
                ((_currentPosition.avgEntryPriceE18 *
                    _currentPosition.amountE18) +
                    (_applyPosition.avgEntryPriceE18 *
                        _applyPosition.amountE18)) /
                (_currentPosition.amountE18 + _applyPosition.amountE18);

            _applyPosition.amountE18 += _currentPosition.amountE18;
        } else {
            if (_currentPosition.amountE18 > _applyPosition.amountE18) {
                _applyPosition.amountE18 =
                    _currentPosition.amountE18 -
                    _applyPosition.amountE18;
                _applyPosition.side = _currentPosition.side;
                _applyPosition.avgEntryPriceE18 = _currentPosition
                    .avgEntryPriceE18;
            } else {
                if (_currentPosition.amountE18 == _applyPosition.amountE18) {
                    _applyPosition.amountE18 = 0;
                    _applyPosition.avgEntryPriceE18 = 0;
                } else {
                    _applyPosition.amountE18 =
                        _applyPosition.amountE18 -
                        _currentPosition.amountE18;
                }
            }
        }
        _applyPosition.lastUpdatedFundingRateE18 = accumulativeFundingRate[
            _marketId
        ];

        return (_applyPosition);
    }

    function _calculatePendingFundingFee(
        IPerpService.Position memory _position,
        int256 _currentAccumulativeFundingRate
    ) internal pure returns (int256) {
        int256 fundingFee = ((_currentAccumulativeFundingRate -
            _position.lastUpdatedFundingRateE18) *
            _position.amountE18.toInt256()) / 1e18;

        return
            _position.side == IPerpService.PositionSide.LONG
                ? fundingFee
                : -fundingFee;
    }

    function _calculateRealizePnl(
        IPerpService.Position memory _position,
        IPerpService.Position memory _applyPosition
    ) internal pure returns (int256) {
        int256 _priceDiff;
        uint256 _amountToReduce;
        if (_position.side != _applyPosition.side) {
            if (_position.side == IPerpService.PositionSide.LONG) {
                _priceDiff =
                    _applyPosition.avgEntryPriceE18.toInt256() -
                    _position.avgEntryPriceE18.toInt256();
            } else {
                _priceDiff =
                    _position.avgEntryPriceE18.toInt256() -
                    _applyPosition.avgEntryPriceE18.toInt256();
            }
            if (_position.amountE18 > _applyPosition.amountE18) {
                _amountToReduce = _applyPosition.amountE18;
            } else {
                _amountToReduce = _position.amountE18;
            }
        }

        return (_amountToReduce.toInt256() * _priceDiff) / 1e18;
    }
}
