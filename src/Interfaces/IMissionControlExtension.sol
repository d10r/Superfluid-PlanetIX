// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// split each operation to a separate function for readability and easier Mission implementation
interface IMissionControlExtension {

    // mission Control PlaceOrder struct
    struct PlaceOrder {
        CollectOrder order;
        uint256 tokenId;
        address tokenAddress;
    }

    struct CollectOrder {
        int256 x;
        int256 y;
        int256 z;
    }
    // user start streaming to the game
    function createRentTiles(address superToken, address renter, PlaceOrder[] memory tiles, int96 flowRate) external;
    // user is streaming and change the rented tiles
    function updateRentTiles(address superToken, address renter, PlaceOrder[] memory addTiles, PlaceOrder[] memory removeTiles, int96 oldFlowRate, int96 flowRate) external;
    // user stop streaming to the game
    function deleteRentTiles(address superToken, address renter) external;
}