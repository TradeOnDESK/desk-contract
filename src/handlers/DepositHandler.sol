// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import {ReentrancyGuardUpgradeable} from "@openzeppelin-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {BaseHandler} from "./BaseHandler.sol";
import {SafeCast} from "@openzeppelin/utils/math/SafeCast.sol";
import {IWETH} from "src/interfaces/tokens/IWETH.sol";
import {IPerpService} from "src/interfaces/services/IPerpService.sol";
import {IAssetService} from "src/interfaces/services/IAssetService.sol";

contract DepositHandler is BaseHandler, ReentrancyGuardUpgradeable {
    using SafeCast for uint256;

    enum DepositAction {
        Process,
        Reject
    }

    address public assetService;

    mapping(uint256 => bool) public isProcessed;

    event LogDeposit(
        bytes32 indexed subaccount,
        address indexed tokenAddress,
        uint256 indexed requestId,
        uint256 amount
    );
    event LogDepositProcessed(
        bytes32 indexed subaccount,
        address indexed tokenAddress,
        uint256 amount
    );
    event LogDepositRejected(
        bytes32 indexed subaccount,
        address indexed tokenAddress,
        uint256 amount
    );
    event LogSetAssetService(
        address indexed oldAssetService,
        address indexed newAssetService
    );

    function initialize(
        address _entryPoint,
        address _assetService
    ) external initializer {
        __initialize(_entryPoint);
        __ReentrancyGuard_init();

        IAssetService(_assetService).BPS();
        assetService = _assetService;
    }

    function _executeAction(bytes memory _data) internal override {
        (
            uint256 _requestId,
            bytes32 _subaccount,
            uint256 _amount,
            address _tokenAddress,
            DepositAction _action
        ) = abi.decode(
                _data,
                (uint256, bytes32, uint256, address, DepositAction)
            );
        if (_subaccount != bytes32(0) && !isProcessed[_requestId]) {
            if (_action == DepositAction.Process) {
                IAssetService(assetService).adjustCollateral(
                    _subaccount,
                    _tokenAddress,
                    _amount.toInt256()
                );
                emit LogDepositProcessed(_subaccount, _tokenAddress, _amount);
            } else {
                emit LogDepositRejected(_subaccount, _tokenAddress, _amount);
            }
            isProcessed[_requestId] = true;
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ADMIN FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function setAssetService(address _assetService) external onlyOwner {
        IAssetService(_assetService).BPS();

        emit LogSetAssetService(assetService, _assetService);
        assetService = _assetService;
    }
}
