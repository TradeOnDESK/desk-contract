// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {IWETH} from "src/interfaces/tokens/IWETH.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import {IWithdrawHandler} from "../interfaces/handlers/IWithdrawHandler.sol";

contract Vault is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    using SafeTransferLib for address;

    struct DepositRequest {
        bytes32 subaccount;
        uint256 amount;
        address tokenAddress;
    }

    struct WithdrawalRequest {
        bytes32 subaccount;
        uint256 amount;
        address tokenAddress;
        uint48 timestamp;
        bool isExecuted;
    }

    uint256 public totalDepositRequests;
    uint256 public totalWithdrawalRequests;
    address public WETH;
    address public withdrawHandler;

    mapping(uint256 requestId => DepositRequest) public depositRequests;
    mapping(uint256 requestId => WithdrawalRequest) public withdrawalRequests;

    mapping(address actor => bool isWhitelisted) public whitelists;
    mapping(address token => uint256 minDepositAmount) public minDeposits;
    mapping(address token => bool isAllow) public withdrawableTokens;
    mapping(address token => address collateralId) public collateralIds;
    mapping(address maintainer => bool isMaintainer) public maintainers;

    event LogDepositRequestCreated(
        uint256 indexed requestId,
        bytes32 indexed subaccount,
        address tokenAddress,
        uint256 amount
    );
    event LogWithdrawRequestCreated(
        uint256 indexed requestId,
        bytes32 indexed subaccount,
        address tokenAddress,
        uint256 amount
    );
    event LogWithdrawRequestProcessed(
        uint256 indexed requestId,
        bytes32 indexed subaccount,
        address receiver,
        address tokenAddress,
        uint256 requestedAmount,
        uint256 transferredAmount
    );
    event LogSetAcceptedToken(address indexed tokenAddress, bool isAccepted);
    event LogSetAssetService(
        address indexed oldAssetService,
        address newAssetService
    );
    event LogSetMinDeposit(address indexed tokenAddress, uint256 amount);
    event LogSetWithdrawableToken(
        address indexed tokenAddress,
        bool isWithdrawable
    );
    event LogSetWhitelist(address indexed user, bool isWhitelisted);
    event LogSetWETH(address indexed weth);
    event LogSetCollateralId(
        address indexed tokenAddress,
        address indexed collateralId
    );
    event LogSetMaintainer(address indexed maintainer, bool isMaintainer);

    error Vault_InvalidAuthentication();
    error Vault_InvalidAddress();
    error Vault_InvalidAmount();
    error Vault_InvalidWithdrawalToken();
    error Vault_InvalidSubaccount();
    error Vault_InvalidRequest();
    error Vault_LessThanMinimumDeposit();
    error Vault_AlreadyExecutedRequest();
    error Vault_ExceedWithdrawableAmount();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _withdrawHandler) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();

        IWithdrawHandler(_withdrawHandler).assetService();
        withdrawHandler = _withdrawHandler;
    }

    modifier onlyAcceptedToken(address _tokenAddress) {
        if (minDeposits[_tokenAddress] == 0) {
            revert Vault_InvalidAddress();
        }
        _;
    }

    modifier onlyMaintainer() {
        if (!maintainers[msg.sender]) {
            revert Vault_InvalidAuthentication();
        }
        _;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     EXTERNAL FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function deposit(
        address _tokenAddress,
        bytes32 _subaccount,
        uint256 _amount
    )
        external
        payable
        nonReentrant
        onlyAcceptedToken(_tokenAddress)
        returns (uint256 _requestId)
    {
        if (msg.value > 0) {
            address _weth = WETH;
            _requestId = _deposit(_weth, _subaccount, msg.value);
            IWETH(_weth).deposit{value: msg.value}();
        } else {
            _requestId = _deposit(_tokenAddress, _subaccount, _amount);
            IERC20(_tokenAddress).safeTransferFrom(
                msg.sender,
                address(this),
                _amount
            );
        }
    }

    function withdraw(
        address _tokenAddress,
        bytes32 _subaccount,
        uint256 _amount
    ) external returns (uint256 _requestId) {
        if (_amount == 0) {
            revert Vault_InvalidAmount();
        }

        if (msg.sender != address(bytes20(_subaccount))) {
            revert Vault_InvalidAuthentication();
        }

        if (!withdrawableTokens[_tokenAddress]) {
            revert Vault_InvalidWithdrawalToken();
        }

        if (
            _amount >
            IWithdrawHandler(withdrawHandler).getWithdrawableAmount(
                _subaccount,
                collateralIds[_tokenAddress]
            )
        ) {
            revert Vault_ExceedWithdrawableAmount();
        }
        uint48 _timestamp = uint48(block.timestamp);
        _requestId = _createWithdrawalRequest(
            _subaccount,
            _tokenAddress,
            _amount,
            _timestamp
        );

        emit LogWithdrawRequestCreated(
            _requestId,
            _subaccount,
            _tokenAddress,
            _amount
        );
    }

    function executeWithdrawal(
        uint256 _requestId,
        uint256 _transferAmount
    ) external {
        if (!whitelists[msg.sender]) {
            revert Vault_InvalidAuthentication();
        }

        WithdrawalRequest storage _request = withdrawalRequests[_requestId];
        uint256 _requestAmount = _request.amount;
        if (_request.isExecuted) {
            revert Vault_AlreadyExecutedRequest();
        }
        if (_request.subaccount == bytes32(0)) {
            revert Vault_InvalidRequest();
        }
        if (_requestAmount < _transferAmount) {
            revert Vault_InvalidAmount();
        }

        _request.isExecuted = true;

        address _token = _request.tokenAddress;
        bytes32 _subaccount = _request.subaccount;
        address _receiver = address(bytes20(_subaccount));
        if (_token == WETH) {
            IWETH(_token).withdraw(_transferAmount);
            _receiver.safeTransferETH(_transferAmount);
        } else {
            IERC20(_token).safeTransfer(_receiver, _transferAmount);
        }

        emit LogWithdrawRequestProcessed(
            _requestId,
            _subaccount,
            _receiver,
            _token,
            _requestAmount,
            _transferAmount
        );
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      OWNER FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function setMaintainer(
        address _maintainer,
        bool _isMaintainer
    ) external onlyOwner {
        maintainers[_maintainer] = _isMaintainer;
        emit LogSetMaintainer(_maintainer, _isMaintainer);
    }

    function setWETH(address _weth) external onlyOwner {
        IWETH(_weth).balanceOf(address(this));
        WETH = _weth;
        emit LogSetWETH(_weth);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    MAINTAINER FUNCTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function setMinDeposit(
        address _tokenAddress,
        uint256 _amount
    ) external onlyMaintainer {
        minDeposits[_tokenAddress] = _amount;
        emit LogSetMinDeposit(_tokenAddress, _amount);
    }

    function setWhitelist(
        address _user,
        bool _isWhitelisted
    ) external onlyMaintainer {
        whitelists[_user] = _isWhitelisted;
        emit LogSetWhitelist(_user, _isWhitelisted);
    }

    function setWithdrawableToken(
        address _tokenAddress,
        bool _isWithdrawable
    ) external onlyMaintainer {
        withdrawableTokens[_tokenAddress] = _isWithdrawable;
        emit LogSetWithdrawableToken(_tokenAddress, _isWithdrawable);
    }

    function setCollateralId(
        address _tokenAddress,
        address _collateralId
    ) external onlyMaintainer {
        collateralIds[_tokenAddress] = _collateralId;
        emit LogSetCollateralId(_tokenAddress, _collateralId);
    }

    function giveUpMaintainer() external onlyMaintainer {
        maintainers[msg.sender] = false;
        emit LogSetMaintainer(msg.sender, false);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     INTERNAL FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _createDepositRequest(
        bytes32 _subaccount,
        address _tokenAddress,
        uint256 _amount
    ) internal returns (uint256 _requestId) {
        _requestId = ++totalDepositRequests;
        depositRequests[_requestId] = DepositRequest(
            _subaccount,
            _amount,
            _tokenAddress
        );
    }

    function _createWithdrawalRequest(
        bytes32 _subaccount,
        address _tokenAddress,
        uint256 _amount,
        uint48 _timestamp
    ) internal returns (uint256 _requestId) {
        _requestId = ++totalWithdrawalRequests;
        withdrawalRequests[_requestId] = WithdrawalRequest(
            _subaccount,
            _amount,
            _tokenAddress,
            _timestamp,
            false
        );
    }

    function _deposit(
        address _tokenAddress,
        bytes32 _subaccount,
        uint256 _amount
    ) internal returns (uint256 _requestId) {
        if (_amount == 0) {
            revert Vault_InvalidAmount();
        }
        if (_subaccount == bytes32(0)) {
            revert Vault_InvalidSubaccount();
        }
        if (_amount < minDeposits[_tokenAddress]) {
            revert Vault_LessThanMinimumDeposit();
        }

        _requestId = _createDepositRequest(_subaccount, _tokenAddress, _amount);

        emit LogDepositRequestCreated(
            _requestId,
            _subaccount,
            _tokenAddress,
            _amount
        );
    }

    receive() external payable {}
}
