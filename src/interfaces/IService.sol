// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

interface IService {
    function setWhitelist(address _whitelist, bool _allowed) external;

    function setMaintainer(address _maintainer, bool _allowed) external;

    function whitelists(address) external view returns (bool);

    function maintainers(address) external view returns (bool);
}
