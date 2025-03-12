// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import {IHandler} from "src/interfaces/IHandler.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import {IEntrypoint} from "src/interfaces/IEntrypoint.sol";

abstract contract BaseHandler is IHandler, OwnableUpgradeable {
    uint256 public constant BPS = 10000;
    address public entrypoint;

    event LogSetEntryPoint(address indexed _old, address indexed _new);

    function __initialize(address _entrypoint) internal onlyInitializing {
        __Ownable_init();

        IEntrypoint(_entrypoint).nextBatchId();
        entrypoint = _entrypoint;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function executeAction(bytes memory _data) external override {
        if (msg.sender != entrypoint) {
            revert BaseHandler_Unauthorized();
        }
        _executeAction(_data);
    }

    function _executeAction(bytes memory _data) internal virtual {}

    function setEntryPoint(address _entrypoint) external onlyOwner {
        emit LogSetEntryPoint(entrypoint, _entrypoint);
        entrypoint = _entrypoint;
    }
}
