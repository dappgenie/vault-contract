// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

interface IVaultManager {

    function createVault(address[] memory _initialAssets, uint256 _performanceFee) external;

    function addTrader(address _trader) external;

    function removeTrader(address _trader) external;

    function executeTrade(uint256 _vaultIndex, address _asset1, uint256 _amount1, address _asset2, uint256 _amount2) external;
}
