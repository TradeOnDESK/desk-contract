// SPDX-License-Identifier: BUSL
pragma solidity 0.8.19;

interface IHandler {
    error BaseHandler_Unauthorized();

    function setEntryPoint(address entrypoint) external;

    function executeAction(bytes memory data) external;
}
