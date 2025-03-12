// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import {BaseService} from "./BaseService.sol";
import {IAssetService} from "src/interfaces/services/IAssetService.sol";
import {IOracleService} from "src/interfaces/services/IOracleService.sol";
import {SafeCast} from "@openzeppelin/utils/math/SafeCast.sol";
import {EnumerableSet} from "@openzeppelin/utils/structs/EnumerableSet.sol";

contract AssetService is BaseService, IAssetService {
    using SafeCast for uint256;
    using SafeCast for int256;
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 public constant BPS = 1e4;
    address public oracleService;
    address public settlementToken;

    uint120 public accumulativeBorrowingRateE18;
    uint120 public accumulativeLendingRateE18;
    uint16 public protocolBorrowingFeeBPS;

    mapping(address token => uint8 decimals) public collateralTokenDecimals;
    mapping(address token => uint256 factorBps) public collateralFactors;
    mapping(address token => uint256 priceFeedId) public priceFeedIds;
    mapping(bytes32 subaccount => mapping(address token => int256 amount))
        public collaterals;
    mapping(bytes32 subaccount => IAssetService.BorrowingAndLendingInfo)
        public borrowingAndLendingInfos;
    mapping(bytes32 subaccount => EnumerableSet.AddressSet activeCollateral)
        private _collateralLists;

    function initialize(
        address _oracleService,
        address _settlementToken,
        uint16 _protocolBorrowingFeeBPS
    ) external initializer {
        __initialize();

        IOracleService(_oracleService).PRICES_PER_SLOT();

        oracleService = _oracleService;
        settlementToken = _settlementToken;
        protocolBorrowingFeeBPS = _protocolBorrowingFeeBPS;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      ONLY WHITELISTED                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function adjustCollateral(
        bytes32 _subaccount,
        address _tokenAddress,
        int256 _amountToAdjust
    ) external onlyWhitelisted {
        if (_tokenAddress == settlementToken) {
            _settlePendingBorrowingFee(_subaccount);
        } else {
            if (
                _amountToAdjust < 0 &&
                -_amountToAdjust > collaterals[_subaccount][_tokenAddress]
            ) {
                revert AssetService_InsufficientCollateral();
            }
        }
        _adjustCollateral(_subaccount, _tokenAddress, _amountToAdjust);

        emit LogAdjustCollateral(_subaccount, _tokenAddress, _amountToAdjust);
    }

    function accumulateBorrowingAndLendingRate(
        uint120 _borrowingRateE18,
        uint120 _lendingRateE18
    ) external onlyWhitelisted {
        uint120 _prevAccumulativeBorrowingRateE18 = accumulativeBorrowingRateE18;
        uint120 _prevAccumulativeLendingRateE18 = accumulativeLendingRateE18;
        uint120 _newAccumulativeBorrowingRateE18;
        uint120 _newAccumulativeLendingRateE18;

        unchecked {
            _newAccumulativeBorrowingRateE18 =
                _borrowingRateE18 +
                _prevAccumulativeBorrowingRateE18;
            _newAccumulativeLendingRateE18 =
                _lendingRateE18 +
                _prevAccumulativeLendingRateE18;
        }
        accumulativeBorrowingRateE18 = _newAccumulativeBorrowingRateE18;
        accumulativeLendingRateE18 = _newAccumulativeLendingRateE18;
        emit LogBorrowingAndLendingRateAccumulated(
            _newAccumulativeBorrowingRateE18,
            _newAccumulativeLendingRateE18
        );
    }

    function transferCollateral(
        bytes32 _subaccountFrom,
        bytes32 _subaccountTo,
        address _tokenAddress,
        int256 _amount
    ) external onlyWhitelisted {
        if (_tokenAddress == settlementToken) {
            _settlePendingBorrowingFee(_subaccountFrom);
            _settlePendingBorrowingFee(_subaccountTo);

            if (
                _amount < 0 &&
                _amount < collaterals[_subaccountFrom][_tokenAddress]
            ) {
                revert AssetService_InvalidAmount();
            }
        } else {
            if (_amount < 0) {
                revert AssetService_InvalidAmount();
            }
        }

        _adjustCollateral(_subaccountFrom, _tokenAddress, -_amount);
        _adjustCollateral(_subaccountTo, _tokenAddress, _amount);
        emit LogTransferCollateral(
            _subaccountFrom,
            _subaccountTo,
            _tokenAddress,
            _amount
        );
    }

    function settlePendingBorrowingFee(
        bytes32 _subaccount
    ) external onlyWhitelisted {
        _settlePendingBorrowingFee(_subaccount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      ONLY MAINTAINER                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function setCollateralFactor(
        address _tokenAddress,
        uint256 _factor
    ) external onlyMaintainer {
        if (_factor > BPS) {
            revert AssetService_InvalidCollateralFactor();
        }
        collateralFactors[_tokenAddress] = _factor;
        emit LogSetCollateralFactor(_tokenAddress, _factor);
    }

    function setAssetPriceId(
        address _tokenAddress,
        uint256 _priceFeedId
    ) external onlyMaintainer {
        priceFeedIds[_tokenAddress] = _priceFeedId;
        emit LogSetAssetPriceId(_tokenAddress, _priceFeedId);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        ONLY OWNER                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function setProtocolBorrowingFeeBPS(uint16 _bps) external onlyOwner {
        emit LogSetProtocolBorrowingFeeBPS(_bps, protocolBorrowingFeeBPS);
        protocolBorrowingFeeBPS = _bps;
    }

    function setSettlementToken(address _settlementToken) external onlyOwner {
        if (_settlementToken == address(0)) {
            revert AssetService_InvalidAddress();
        }
        settlementToken = _settlementToken;
        emit LogSetSettlementToken(_settlementToken);
    }

    function setAccumulativeBorrowingRate(uint120 _rateE18) external onlyOwner {
        accumulativeBorrowingRateE18 = _rateE18;
    }

    function setAccumulativeLendingRate(uint120 _rateE18) external onlyOwner {
        accumulativeLendingRateE18 = _rateE18;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      Init Setter Function                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    struct SetSubaccountInfo {
        bytes32 subaccount;
        IAssetService.BorrowingAndLendingInfo borrowingAndLendingInfo;
    }

    function initSetBorrowingAndLendingInfos(
        SetSubaccountInfo[] calldata _data
    ) external onlyOwner {
        uint256 _len = _data.length;
        uint256 _i = 0;
        for (; _i < _len; ) {
            _initSetBorrowingAndLendingInfo(
                _data[_i].subaccount,
                _data[_i].borrowingAndLendingInfo
            );
            unchecked {
                ++_i;
            }
        }
    }

    function _initSetBorrowingAndLendingInfo(
        bytes32 _subaccount,
        BorrowingAndLendingInfo calldata _info
    ) internal {
        borrowingAndLendingInfos[_subaccount] = _info;
    }

    struct SetCollateral {
        bytes32 subaccount;
        address tokenAddress;
        int256 amountToSet;
    }

    function initSetCollaterals(
        SetCollateral[] calldata _data
    ) external onlyOwner {
        uint256 _len = _data.length;
        uint256 _i = 0;
        for (; _i < _len; ) {
            _initSetCollateral(
                _data[_i].subaccount,
                _data[_i].tokenAddress,
                _data[_i].amountToSet
            );
            unchecked {
                ++_i;
            }
        }
    }

    function _initSetCollateral(
        bytes32 _subaccount,
        address _tokenAddress,
        int256 _amountToSet
    ) internal onlyOwner {
        collaterals[_subaccount][_tokenAddress] = _amountToSet;
        _collateralLists[_subaccount].add(_tokenAddress);
    }

    function setCollateralTokenDecimals(
        address _tokenAddress,
        uint8 _decimals
    ) external onlyMaintainer {
        collateralTokenDecimals[_tokenAddress] = _decimals;
        emit LogSetCollateralTokenDecimals(_tokenAddress, _decimals);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function getSubaccountTotalMargin(
        bytes32 _subaccount
    ) external view returns (int256 _collateralValueE18) {
        uint256 _length = _collateralLists[_subaccount].length();
        uint256 _i;
        uint256 _priceE18;
        address _tokenAddress;
        int256 _collatAmount;
        for (; _i < _length; ) {
            _tokenAddress = _collateralLists[_subaccount].at(_i);
            _priceE18 = IOracleService(oracleService).getPrice(
                priceFeedIds[_tokenAddress]
            );
            _collatAmount = collaterals[_subaccount][_tokenAddress];
            uint8 _decimals = collateralTokenDecimals[_tokenAddress];
            if (_collatAmount > 0) {
                _collateralValueE18 +=
                    (_collatAmount *
                        _priceE18.toInt256() *
                        collateralFactors[_tokenAddress].toInt256()) /
                    (10 ** _decimals).toInt256() /
                    int256(BPS);
            } else {
                _collateralValueE18 +=
                    (_collatAmount * _priceE18.toInt256()) /
                    (10 ** _decimals).toInt256();
            }

            unchecked {
                ++_i;
            }
        }
    }

    function getAssetPrice(
        address _tokenAddress
    ) external view returns (uint256 _priceE18) {
        _priceE18 = IOracleService(oracleService).getPrice(
            priceFeedIds[_tokenAddress]
        );
    }

    function getCurrentProtocolBorrowingAndLendingInfo()
        public
        view
        returns (IAssetService.BorrowingAndLendingInfo memory _currentInfo)
    {
        _currentInfo = IAssetService.BorrowingAndLendingInfo({
            borrowingRateE18: accumulativeBorrowingRateE18,
            lendingRateE18: accumulativeLendingRateE18
        });
    }

    function getSubaccountPendingBorrowingFee(
        bytes32 _subaccount
    ) external view returns (int256 _borrowingFeeE18) {
        IAssetService.BorrowingAndLendingInfo
            memory _currentInfo = getCurrentProtocolBorrowingAndLendingInfo();
        IAssetService.BorrowingAndLendingInfo
            memory _userInfo = borrowingAndLendingInfos[_subaccount];

        _borrowingFeeE18 = _calculateBorrowingFeeE18(
            _userInfo,
            _currentInfo,
            collaterals[_subaccount][settlementToken],
            collateralTokenDecimals[settlementToken]
        );
    }

    function getSubaccountCollateralList(
        bytes32 _subaccount
    ) external view returns (address[] memory _subaccountCollateralLists) {
        uint256 _length = _collateralLists[_subaccount].length();
        _subaccountCollateralLists = new address[](_length);

        uint256 _i = 0;
        for (; _i < _length; ) {
            _subaccountCollateralLists[_i] = _collateralLists[_subaccount].at(
                _i
            );
            unchecked {
                ++_i;
            }
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     INTERNAL FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _adjustCollateral(
        bytes32 _subaccount,
        address _tokenAddress,
        int256 _amountToAdjust
    ) internal {
        collaterals[_subaccount][_tokenAddress] += _amountToAdjust;

        if (!_collateralLists[_subaccount].contains(_tokenAddress)) {
            _collateralLists[_subaccount].add(_tokenAddress);
        }
        if (collaterals[_subaccount][_tokenAddress] == 0) {
            _collateralLists[_subaccount].remove(_tokenAddress);
        }
    }

    function _calculateBorrowingFeeE18(
        IAssetService.BorrowingAndLendingInfo memory _userRate,
        IAssetService.BorrowingAndLendingInfo memory _currentGlobalRate,
        int256 _settlementAssetBalance,
        uint8 _decimals
    ) internal pure returns (int256 _borrowingFee) {
        if (_settlementAssetBalance == 0) {
            return 0;
        }
        if (_settlementAssetBalance < 0) {
            _borrowingFee =
                (uint256(
                    _currentGlobalRate.borrowingRateE18 -
                        _userRate.borrowingRateE18
                ).toInt256() * _settlementAssetBalance) /
                int256(10 ** _decimals);
        } else {
            _borrowingFee =
                (uint256(
                    _currentGlobalRate.lendingRateE18 - _userRate.lendingRateE18
                ).toInt256() * _settlementAssetBalance) /
                int256(10 ** _decimals);
        }
        _borrowingFee *= -1;
    }

    function _settlePendingBorrowingFee(bytes32 _subaccount) internal {
        IAssetService.BorrowingAndLendingInfo
            memory _currentInfo = getCurrentProtocolBorrowingAndLendingInfo();
        IAssetService.BorrowingAndLendingInfo
            memory _userInfo = borrowingAndLendingInfos[_subaccount];
        if (
            _currentInfo.borrowingRateE18 == _userInfo.borrowingRateE18 &&
            _currentInfo.lendingRateE18 == _userInfo.lendingRateE18
        ) {
            return;
        }

        int256 _settlementTokenBalance = collaterals[_subaccount][
            settlementToken
        ];

        if (_settlementTokenBalance > 0) {
            _payLendingFeeToSubaccount(
                _subaccount,
                _userInfo.lendingRateE18,
                _currentInfo.lendingRateE18,
                _settlementTokenBalance
            );
        } else if (_settlementTokenBalance < 0) {
            _receiveBorrowingFeeFromSubaccount(
                _subaccount,
                _userInfo.borrowingRateE18,
                _currentInfo.borrowingRateE18,
                _settlementTokenBalance
            );
        }
        borrowingAndLendingInfos[_subaccount] = _currentInfo;
    }

    function _payLendingFeeToSubaccount(
        bytes32 _subaccount,
        uint128 _userLendingRateE18,
        uint128 _protocolLendingRateE18,
        int256 _positiveSettlementAssetBalance
    ) internal {
        uint256 _lendingFee = (uint256(
            _protocolLendingRateE18 - _userLendingRateE18
        ) * _positiveSettlementAssetBalance.toUint256()) / 1e18;
        _adjustCollateral(_subaccount, settlementToken, _lendingFee.toInt256());
        emit LogSubaccountReceiveLendingFee(_subaccount, _lendingFee);
    }

    function _receiveBorrowingFeeFromSubaccount(
        bytes32 _subaccount,
        uint128 _userBorrowingRateE18,
        uint128 _protocolBorrowingRateE18,
        int256 _negativeSettlementAssetBalance
    ) internal {
        int256 _borrowingFee = (uint256(
            _protocolBorrowingRateE18 - _userBorrowingRateE18
        ).toInt256() * _negativeSettlementAssetBalance) / 1e18;
        _adjustCollateral(_subaccount, settlementToken, _borrowingFee);
        emit LogSubaccountPayBorrowingFee(_subaccount, uint256(-_borrowingFee));
    }
}
