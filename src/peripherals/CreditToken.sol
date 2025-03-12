// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import {ERC20Upgradeable} from "@openzeppelin-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin-upgradeable/access/Ownable2StepUpgradeable.sol";

contract CreditToken is ERC20Upgradeable, Ownable2StepUpgradeable {
    address public vault;

    event LogSetVault(address indexed vault);

    error CreditToken_NotAllowedToTransfer();
    error CreditToken_InvalidVaultAddress();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        string calldata name_,
        string calldata symbol_,
        address _vault
    ) public initializer {
        __ERC20_init(name_, symbol_);
        __Ownable2Step_init();

        _setVault(_vault);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       ADMIN FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function setVault(address _vault) public onlyOwner {
        _setVault(_vault);
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) public onlyOwner {
        _burn(from, amount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     INTERNAL FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _beforeTokenTransfer(
        address,
        address to,
        uint256
    ) internal view override(ERC20Upgradeable) {
        if (msg.sender != owner() && to != vault) {
            revert CreditToken_NotAllowedToTransfer();
        }
    }

    function _setVault(address _vault) internal {
        if (_vault == address(0)) {
            revert CreditToken_InvalidVaultAddress();
        }

        vault = _vault;
        emit LogSetVault(_vault);
    }
}
