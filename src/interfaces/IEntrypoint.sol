// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

interface IEntrypoint {
    error Entrypoint_HandlerIsNotSet();
    error Entrypoint_InvalidNonce();
    error Entrypoint_InvalidBatchId();
    error Entrypoint_InvalidSignature();
    error Entrypoint_InvalidTxId();
    error Entrypoint_Unauthorized();

    event LogSetExecutor(address executor, bool allowed);
    event LogSetBatchId(uint256 oldBatchId, uint256 newBatchId);
    event LogSetMaintainer(address maintainer, bool allowed);
    event LogSetLatestTxId(uint256 oldLatestTxId, uint256 newLatestTxId);

    enum ActionType {
        Deposit,
        Withdraw,
        Trade,
        Liquidate,
        CollateralSeize,
        Admin,
        ExecutionFee,
        Swap
    }

    struct Transaction {
        uint256 id;
        ActionType actionType;
        bytes data;
    }

    function setExecutor(address executor, bool allowed) external;

    function setHandler(uint8 actionType, address handler) external;

    function submitTransactions(
        Transaction[] calldata transactions,
        uint256 batchId
    ) external;

    function isExecutor(address executor) external view returns (bool);

    function handlers(uint8 actionType) external view returns (address);

    function latestTxId() external view returns (uint256);

    function nextBatchId() external view returns (uint256);
}
