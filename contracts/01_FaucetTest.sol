// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/**
 * @title FaucetTest
 * @notice Quickest way to test Pythia — no LINK needed.
 *         Calls the pre-funded Pythia Faucet (5 free requests/address/day).
 *
 * @dev The Faucet is already deployed on Polygon mainnet and pre-funded.
 *      Your contract calls it; the Faucet pays the LINK fee on your behalf.
 *
 * Faucet address (Polygon mainnet): 0x640fC3B9B607E324D7A3d89Fcb62C77Cc0Bd420A
 * Available tokens: pol, aave, morpho, crv, bal, comp, zro, w, quick, uniswap, wormhole, lido-dao, arpa
 * Indicators:       USD_PRICE, EMA_5M_20, EMA_1H_20, RSI_1H_14, RSI_1D_14, VWAP_24H,
 *                   BOLLINGER_UPPER_5M, BOLLINGER_LOWER_5M, VOLATILITY_30D, LIQUIDITY_SCORE
 * Feed format:      {token}_{INDICATOR}  e.g. "pol_RSI_1D_14", "aave_EMA_1H_20"
 *
 * Docs: https://pythia.c3x-solutions.com
 */
interface IPythiaFaucet {
    function requestIndicator(string calldata feed) external returns (bytes32);
    function lastValue() external view returns (uint256);
    function lastFeed() external view returns (string memory);
}

contract FaucetTest {
    IPythiaFaucet public constant FAUCET =
        IPythiaFaucet(0x640fC3B9B607E324D7A3d89Fcb62C77Cc0Bd420A);

    uint256 public lastValue;
    string  public lastFeed;

    event DataReceived(string feed, uint256 value);

    /**
     * @notice Request any indicator via the free faucet.
     *         No LINK required — rate limited to 5 req/address/day.
     * @param feed e.g. "pol_RSI_1D_14", "aave_EMA_1H_20", "morpho_VOLATILITY_30D"
     */
    function requestData(string calldata feed) external {
        FAUCET.requestIndicator(feed);
    }

    /**
     * @notice Read the last fulfilled value from the faucet.
     *         Call after your requestIndicator tx has been fulfilled (~30s on mainnet).
     */
    function readLatest() external view returns (uint256 value, string memory feed) {
        return (FAUCET.lastValue(), FAUCET.lastFeed());
    }
}
