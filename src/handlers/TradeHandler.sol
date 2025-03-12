// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import {BaseHandler} from "./BaseHandler.sol";
import {ECDSA} from "@openzeppelin/utils/cryptography/ECDSA.sol";

import {Math} from "@openzeppelin/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/utils/math/SafeCast.sol";

import {IAssetService} from "src/interfaces/services/IAssetService.sol";
import {IPerpService} from "src/interfaces/services/IPerpService.sol";

contract TradeHandler is BaseHandler {
    using SafeCast for uint256;
    using SafeCast for int256;

    uint256 public constant MAX_TRADING_FEE_BPS = 100;

    enum OrderSide {
        LONG,
        SHORT
    }

    struct Order {
        uint256 amount;
        uint256 price;
        uint8 side;
        uint32 marketId;
        uint64 nonce;
        bytes32 subaccount;
    }

    struct MatchOrders {
        Order taker;
        Order maker;
        int256 takerTradingFee;
        int256 makerTradingFee;
        uint256 matchQuantity;
    }

    struct MatchResult {
        int256 makerPnL;
        int256 takerPnL;
        int256 makerFunding;
        int256 takerFunding;
    }

    address public perpService;
    address public assetService;
    address public settlementToken;

    event LogTrade(
        bytes32 indexed makerSubaccount,
        bytes32 indexed TakerSubaccount,
        uint32 marketId,
        uint256 executedPrice,
        uint256 matchQuantity,
        int256 makerFee,
        int256 takerFee,
        MatchResult result
    );
    event LogSettleTradingFee(
        bytes32 indexed makerSubaccount,
        bytes32 indexed takerSubaccount,
        uint256 makerFee,
        uint256 takerFee
    );
    event LogSetAssetService(
        address indexed oldAssetService,
        address indexed newAssetService
    );
    event LogSetPerpService(
        address indexed oldPerpService,
        address indexed newPerpService
    );
    event LogSetSettlementToken(
        address indexed oldSettlementToken,
        address indexed newSettlementToken
    );

    error TradeHandler_InvalidMarket();
    error TradeHandler_InvalidPrice();
    error TradeHandler_InvalidOrder();
    error TradeHandler_TradingFeeMismatch();
    error TradeHandler_InvalidOrdersPair();
    error TradeHandler_TradingFeeExceedsMax();
    error TradeHandler_InvalidMatchQuantity();
    error TradeHandler_InvalidToken();

    function initialize(
        address _entrypoint,
        address _assetService,
        address _perpService,
        address _settlementToken
    ) external initializer {
        __initialize(_entrypoint);

        IAssetService(_assetService).BPS();
        IPerpService(_perpService).BPS();
        IAssetService(_assetService).collateralTokenDecimals(_settlementToken);

        assetService = _assetService;
        perpService = _perpService;
        settlementToken = _settlementToken;
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

    function setSettlementToken(address _settlementToken) external onlyOwner {
        emit LogSetSettlementToken(settlementToken, _settlementToken);
        settlementToken = _settlementToken;
    }

    function _executeAction(bytes memory _data) internal override {
        (MatchOrders memory _orders, bytes32 _protocolFeeSubaccount) = abi
            .decode(_data, (MatchOrders, bytes32));

        Order memory _taker = _orders.taker;
        Order memory _maker = _orders.maker;
        uint256 _matchQuantity = _orders.matchQuantity;

        _validateMatchOrders(_taker, _maker, _matchQuantity);
        MatchResult memory _result = _matchOrders(
            _orders,
            _protocolFeeSubaccount
        );

        emit LogTrade(
            _maker.subaccount,
            _taker.subaccount,
            _taker.marketId,
            _maker.price,
            _orders.matchQuantity,
            _orders.makerTradingFee,
            _orders.takerTradingFee,
            _result
        );
    }

    function _matchOrders(
        MatchOrders memory _orders,
        bytes32 _protocolFeeSubaccount
    ) internal returns (MatchResult memory _result) {
        IPerpService _perpService = IPerpService(perpService);
        IPerpService.MarketInfo memory _market = _perpService.getMarket(
            _orders.maker.marketId
        );
        if (_market.mmf == 0) {
            revert TradeHandler_InvalidMarket();
        }

        int256 _maxTradingFeeE18 = ((_orders.matchQuantity *
            _orders.maker.price *
            MAX_TRADING_FEE_BPS) /
            BPS /
            1e18).toInt256();
        if (
            _orders.takerTradingFee > _maxTradingFeeE18 ||
            _orders.makerTradingFee > _maxTradingFeeE18
        ) {
            revert TradeHandler_TradingFeeExceedsMax();
        }

        if (_orders.takerTradingFee + _orders.makerTradingFee < 0) {
            revert TradeHandler_TradingFeeMismatch();
        }

        {
            IPerpService.Position memory _applyTakerPosition = IPerpService
                .Position({
                    amountE18: _orders.matchQuantity,
                    avgEntryPriceE18: _orders.maker.price,
                    side: IPerpService.PositionSide(_orders.taker.side),
                    lastUpdatedFundingRateE18: int256(0)
                });
            IPerpService.FundingAndPnL memory _takerNet = _perpService
                .applyPosition(
                    _orders.taker.subaccount,
                    _orders.taker.marketId,
                    _applyTakerPosition
                );
            _settle(
                _orders.taker.subaccount,
                _takerNet.pnlE18,
                _orders.takerTradingFee,
                _takerNet.fundingE18,
                _protocolFeeSubaccount
            );
            _result.takerPnL = _takerNet.pnlE18;
            _result.takerFunding = _takerNet.fundingE18;
        }

        {
            IPerpService.Position memory _applyMakerPosition = IPerpService
                .Position({
                    amountE18: _orders.matchQuantity,
                    avgEntryPriceE18: _orders.maker.price,
                    side: IPerpService.PositionSide(_orders.maker.side),
                    lastUpdatedFundingRateE18: int256(0)
                });
            IPerpService.FundingAndPnL memory _makerNet = _perpService
                .applyPosition(
                    _orders.maker.subaccount,
                    _orders.maker.marketId,
                    _applyMakerPosition
                );
            _settle(
                _orders.maker.subaccount,
                _makerNet.pnlE18,
                _orders.makerTradingFee,
                _makerNet.fundingE18,
                _protocolFeeSubaccount
            );
            _result.makerPnL = _makerNet.pnlE18;
            _result.makerFunding = _makerNet.fundingE18;
        }
    }

    function _validateMatchOrders(
        Order memory _taker,
        Order memory _maker,
        uint256 _matchQuantity
    ) internal pure {
        bool isSameSide = _taker.side == _maker.side;
        bool isDiffMarket = _taker.marketId != _maker.marketId;

        if (isSameSide || isDiffMarket) {
            revert TradeHandler_InvalidOrdersPair();
        }

        if (_maker.price == 0) {
            revert TradeHandler_InvalidPrice();
        }

        if (_maker.amount == 0 || _taker.amount == 0) {
            revert TradeHandler_InvalidOrder();
        }

        if (
            _matchQuantity > _maker.amount ||
            _matchQuantity > _taker.amount ||
            _matchQuantity == 0
        ) {
            revert TradeHandler_InvalidMatchQuantity();
        }
    }

    function _settle(
        bytes32 _subaccount,
        int256 _realizePnlE18,
        int256 _tradingFeeE18,
        int256 _fundingFeeE18,
        bytes32 _protocolFeeSubaccount
    ) internal {
        IAssetService _assetService = IAssetService(assetService);

        int256 _netE18 = _realizePnlE18 - _fundingFeeE18;
        address _settlementToken = settlementToken;
        uint8 _settlementTokenDecimal = _assetService.collateralTokenDecimals(
            _settlementToken
        );

        if (_settlementTokenDecimal == 0) {
            revert TradeHandler_InvalidToken();
        }

        _assetService.adjustCollateral(
            _subaccount,
            _settlementToken,
            _netE18 / (10 ** (18 - _settlementTokenDecimal)).toInt256()
        );
        if (_tradingFeeE18 > 0) {
            _assetService.transferCollateral(
                _subaccount,
                _protocolFeeSubaccount,
                _settlementToken,
                _tradingFeeE18 /
                    uint256(10 ** (18 - _settlementTokenDecimal)).toInt256()
            );
        }
        if (_tradingFeeE18 < 0) {
            _assetService.transferCollateral(
                _protocolFeeSubaccount,
                _subaccount,
                _settlementToken,
                -_tradingFeeE18 /
                    uint256(10 ** (18 - _settlementTokenDecimal)).toInt256()
            );
        }
    }
}
