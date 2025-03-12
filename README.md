# Smart Contracts for State Synchronization for Crypto Futures Trading Platform

This repository contains the smart contracts used by our crypto futures trading platform. These contracts serve as a critical component for maintaining transparency, ensuring the alignment of backend logic with on-chain states, and managing user actions such as deposits, withdrawals, and trades.

## Overview

Our platform processes order executions, position management, and fund movements (fees, profit, and loss) within backend servers. After processing, all relevant events are recorded on-chain through our smart contracts. These contracts act as after-the-fact evidence of backend operations, ensuring transparency and consistency between backend logic and on-chain states.

If discrepancies arise between backend servers and the smart contract logic, **state desynchronization** may occur, preventing users from performing essential actions (e.g., withdrawals). Therefore, it is imperative that our protocol maintains logical accuracy and consistency between backend processes and smart contracts.

---

## Architecture

### 1. **Accounting Contracts**

These contracts handle backend event data and store accounting information. They consist of the following components:

- **Entrypoint Contract**  
  All backend events are routed through this contract as the first point of contact.

- **Handlers**  
  Events from the entrypoint are routed to specific handler contracts based on their type (e.g., trade events, withdrawals).

- **Services**  
  These contracts act as storage for state information:
  - **Asset Service**: Manages collateral-related state.
  - **Perp Service**: Manages positions and related state.

---

### 2. **Peripheral Contracts**

These contracts act as intermediaries between on-chain requests and backend server processes, facilitating seamless communication.

- **Vault Contract**  
  Accepts and disperses collateral tokens based on user deposit and withdrawal requests.

---

## Event Types

### 1. **Deposit**

- **Description**: Increases the user's collateral balance on the platform.
- **Business Logic**:  
  When a user deposits assets (e.g., stablecoins), this event reflects the increase in their available balance. Backend servers confirm the transaction and emit this event on-chain. The smart contract updates the user’s collateral state to ensure they can trade or maintain positions.

### 2. **Withdraw**

- **Description**: Decreases the user's collateral balance.
- **Business Logic**:  
  This event is triggered when a user initiates a withdrawal. The backend server ensures that the user has sufficient balance, and the smart contract processes the request by dispersing the correct amount of assets from the **Vault Contract**. It also ensures the withdrawal does not leave any positions under-collateralized.

### 3. **Orders Match**

- **Description**: Represents the lifecycle of trades and their impact on the user's account.
- **Business Logic**:  
  This event handles:
  - **Trade Execution**: Records a buy or sell order that matched with another order.
  - **Open Position**: Updates the user’s position state when a new trade opens.
  - **Close Position**: Emits when the user’s open position is fully or partially closed.
  - **Settle Profit and Loss (PnL)**: The smart contract calculates PnL when closing positions. If profitable, the user’s balance increases; if not, it decreases.
  - **Fees Charged**: Deducts trading or protocol fees from the user’s account upon trade execution.

### 4. **Account Flagging for Liquidation**

- **Description**: Marks accounts that are eligible for liquidation.
- **Business Logic**:  
  This event ensures that under-collateralized accounts are flagged for liquidation. The backend system evaluates whether the account's margin ratio has fallen below a certain threshold. Once flagged, the system ensures that no new positions can be opened, and the user’s assets become subject to potential collateral seizure.

### 5. **Mark Price Update**

- **Description**: Updates the price used for calculating profit, loss, and liquidation.
- **Business Logic**:  
  The **Mark Price** reflects the fair market value of the traded asset. This event is crucial for calculating real-time PnL and determining whether accounts are at risk of liquidation. It ensures that both backend and smart contract systems use consistent price data for margin calculations.

### 6. **Collateral Seize**

- **Description**: Seizes a portion of collateral from accounts flagged for liquidation.
- **Business Logic**:  
  When an account is flagged for liquidation, this event allows the protocol to seize a portion of the user's collateral to cover losses. This ensures that the platform remains solvent and users are protected from systemic risks. Only accounts marked for liquidation can have their collateral seized.

### 7. **Miscellaneous Configuration Events**

- **Description**: Handles system-wide configuration changes.
- **Business Logic**:  
  These events are used by the protocol’s governance or administration team to update various settings, including:
  - **Open Market**: Allows new assets or trading pairs to become available for trading.
  - **Set Protocol Account**: Designates specific accounts with administrative privileges or assigns protocol-level accounts (e.g., for fee collection or treasury management).

---

## Contributing

Feel free to submit pull requests for improvements or open issues for bug reporting. We welcome community contributions to enhance the functionality and robustness of the platform.

---

## License

This project is licensed under the BUSL License. See the [LICENSE](./LICENSE) file for more details.
