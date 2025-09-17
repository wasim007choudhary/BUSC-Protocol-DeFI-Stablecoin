// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
/**
 * @title OracleLib
 * @author Wasim Choudhary
 * @notice Library for validating Chainlink oracle data freshness.
 *
 * @dev
 * This library ensures that price data retrieved from Chainlink is not stale.
 * If the oracle data has not been updated within an acceptable time frame, the
 * function will revert. This behavior is intentional and critical for protocol
 * safety: preventing the use of outdated or unreliable price data.
 *
 * Design Rationale:
 * - If Chainlink oracles stop updating, the BUSCmotor protocol will become
 *   temporarily unusable (frozen). This fail-safe mechanism protects user funds
 *   from being mispriced due to stale oracle values.
 */

library OracleLib {
    error OracleLib___stalePriceCheckLatestRoundData__StalePrice();

    uint256 private constant PRICEFEED_TIMEOUT = 2 hours; // intended, else update comment/value

    function stalePriceCheckLatestRoundData(AggregatorV3Interface priceFeed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            priceFeed.latestRoundData();

        uint256 secondsSince = block.timestamp - updatedAt;
        if (secondsSince > PRICEFEED_TIMEOUT) {
            revert OracleLib___stalePriceCheckLatestRoundData__StalePrice();
        }
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}
