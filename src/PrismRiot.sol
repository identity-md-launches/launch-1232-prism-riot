// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Prism Riot (PRIO)
/// @notice Fixed supply ERC-20 with 18 decimals and no administrative powers.
/// @dev The immediate deployer receives the entire supply, including when deployed by a factory.
contract PrismRiot is ERC20 {
    /// @notice One billion PRIO expressed in the token's smallest units.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20("Prism Riot", "PRIO") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
