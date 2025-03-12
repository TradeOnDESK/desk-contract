// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import { OwnableUpgradeable } from "@openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import { IService } from "src/interfaces/IService.sol";

contract BaseService is IService, OwnableUpgradeable {
    event LogSetWhitelist(address indexed whitelist, bool allowed);
    event LogSetMaintainer(address indexed maintainer, bool allowed);

    error BaseService_Unauthorized();

    mapping(address => bool) public whitelists;
    mapping(address => bool) public maintainers;

    modifier onlyWhitelisted() {
        if (!whitelists[msg.sender]) {
            revert BaseService_Unauthorized();
        }
        _;
    }

    modifier onlyMaintainer() {
        if (!maintainers[msg.sender]) {
            revert BaseService_Unauthorized();
        }
        _;
    }
    /// @custom:oz-upgrades-unsafe-allow constructor

    constructor() {
        _disableInitializers();
    }

    function __initialize() internal onlyInitializing {
        __Ownable_init();
    }

    function setWhitelist(address _whitelist, bool _allowed) external override onlyOwner {
        whitelists[_whitelist] = _allowed;
        emit LogSetWhitelist(_whitelist, _allowed);
    }

    function setMaintainer(address _maintainer, bool _allowed) external override onlyOwner {
        maintainers[_maintainer] = _allowed;
        emit LogSetMaintainer(_maintainer, _allowed);
    }
}
