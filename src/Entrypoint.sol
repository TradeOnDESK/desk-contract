// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import {Ownable2StepUpgradeable} from "@openzeppelin-upgradeable/access/Ownable2StepUpgradeable.sol";
import {IHandler} from "src/interfaces/IHandler.sol";
import {IEntrypoint} from "src/interfaces/IEntrypoint.sol";

contract Entrypoint is IEntrypoint, Ownable2StepUpgradeable {
    uint256 public nextBatchId;
    uint256 public latestTxId;
    mapping(address => bool) public isExecutor;
    mapping(uint8 => address) public handlers;
    mapping(address => bool) public isMaintainer;

    modifier onlyExecutor() {
        if (!isExecutor[msg.sender]) {
            revert Entrypoint_Unauthorized();
        }
        _;
    }

    modifier onlyMaintainer() {
        if (!isMaintainer[msg.sender]) {
            revert Entrypoint_Unauthorized();
        }
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() external initializer {
        __Ownable_init();
        nextBatchId = 1;
        latestTxId = 0;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      OWNER FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function setMaintainer(
        address _maintainer,
        bool _allowed
    ) external onlyOwner {
        isMaintainer[_maintainer] = _allowed;
        emit LogSetMaintainer(_maintainer, _allowed);
    }

    function setHandler(
        uint8 _actionType,
        address _handler
    ) external onlyOwner {
        handlers[_actionType] = _handler;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    MAINTAINER FUNCTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function setExecutor(
        address _executor,
        bool _allowed
    ) external onlyMaintainer {
        isExecutor[_executor] = _allowed;
        emit LogSetExecutor(_executor, _allowed);
    }

    function setStartBatchId(uint256 _nextBatchId) external onlyMaintainer {
        if (_nextBatchId < nextBatchId) {
            revert Entrypoint_InvalidBatchId();
        }
        emit LogSetBatchId(nextBatchId, _nextBatchId);
        nextBatchId = _nextBatchId;
    }

    function setLatestTxId(uint256 _latestTxId) external onlyMaintainer {
        latestTxId = _latestTxId;
        emit LogSetLatestTxId(latestTxId, _latestTxId);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      EXECUTOR FUNCTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function submitTransactions(
        Transaction[] calldata _transactions,
        uint256 _batchId
    ) external onlyExecutor {
        if (_batchId != nextBatchId) {
            revert Entrypoint_InvalidBatchId();
        }
        uint256 _len = _transactions.length;
        uint256 _i;
        address _handler;
        uint256 _txId = latestTxId;
        for (_i; _i < _len; ) {
            _handler = handlers[uint8(_transactions[_i].actionType)];
            if (_handler == address(0)) {
                revert Entrypoint_HandlerIsNotSet();
            }
            if (_transactions[_i].id != _txId + 1) {
                revert Entrypoint_InvalidTxId();
            }
            IHandler(_handler).executeAction(_transactions[_i].data);

            _txId = _transactions[_i].id;

            unchecked {
                ++_i;
            }
        }
        latestTxId = _txId;
        unchecked {
            ++nextBatchId;
        }
    }
}
