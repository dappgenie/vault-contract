// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

interface IAssetVault {
    function setAssetToOracle(address _asset, address _oracle) external;

    function updatePoolFee(uint8 _newPoolFee) external;

    function updateProfitFee(uint8 _newProfitFee) external;


    function deposit(address _asset, uint256 _amount) external;
    function withdraw(address _asset) external;
    function trade(address _asset1, uint256 _amount1, address _asset2) external;

    // function estimateAssetValue(address _asset, uint256 _amount) public view returns (uint256 valueUSD);

    // function estimateAssetAmount(address _asset, uint256 _valueUSD) public view returns (uint256 amount);

    // function pointsValueInUSD(uint256 points) public view returns (uint256);

    // function estimateAssetValueInUSD(address _asset) public view returns (uint256 total, uint256 valueInUsd);
}
