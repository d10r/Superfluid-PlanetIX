pragma solidity ^0.8.0;

import "forge-std/Console.sol";
import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import { SuperfluidFrameworkDeployer, SuperfluidTester, Superfluid, ConstantFlowAgreementV1, CFAv1Library } from "./utils/SuperfluidTester.sol";
import { ERC1820RegistryCompiled } from "@superfluid-finance/ethereum-contracts/contracts/libs/ERC1820RegistryCompiled.sol";
import { MissionControlStream } from "./../src/MissionControlStream.sol";
import { IMissionControlExtension } from "./../src/interfaces/IMissionControlExtension.sol";
import { MockMissionControl } from "./mocks/MockMissionControl.sol";

contract MissionControlTest is SuperfluidTester {

    event TerminationCallReverted(address indexed sender);

    /// @dev This is required by solidity for using the CFAv1Library in the tester
    using CFAv1Library for CFAv1Library.InitData;

    SuperfluidFrameworkDeployer internal immutable sfDeployer;
    SuperfluidFrameworkDeployer.Framework internal sf;
    Superfluid host;
    ConstantFlowAgreementV1 cfa;
    CFAv1Library.InitData internal cfaV1Lib;

    MockMissionControl mockMissionCtrl;
    MissionControlStream missionCtrlStream;

    constructor() SuperfluidTester(3) {
        vm.startPrank(admin);
        vm.etch(ERC1820RegistryCompiled.at, ERC1820RegistryCompiled.bin);
        sfDeployer = new SuperfluidFrameworkDeployer();
        sf = sfDeployer.getFramework();
        host = sf.host;
        cfa = sf.cfa;
        cfaV1Lib = CFAv1Library.InitData(host,cfa);
        vm.stopPrank();
    }

    function setUp() public virtual {
        (token1, superToken1) = sfDeployer.deployWrapperSuperToken("Energy", "Energy", 18, type(uint256).max);
        (token2, superToken2) = sfDeployer.deployWrapperSuperToken("PIX", "PIX", 18, type(uint256).max);

        for (uint32 i = 0; i < N_TESTERS; ++i) {
            token1.mint(TEST_ACCOUNTS[i], INIT_TOKEN_BALANCE);
            token2.mint(TEST_ACCOUNTS[i], INIT_TOKEN_BALANCE);
            vm.startPrank(TEST_ACCOUNTS[i]);
            token1.approve(address(superToken1), INIT_SUPER_TOKEN_BALANCE);
            token2.approve(address(superToken2), INIT_SUPER_TOKEN_BALANCE);
            superToken1.upgrade(INIT_SUPER_TOKEN_BALANCE);
            superToken2.upgrade(INIT_SUPER_TOKEN_BALANCE);
            vm.stopPrank();
        }
        deployMockMissionControl();
        deployMissionControlStream();
    }

    function deployMockMissionControl() public {
        vm.startPrank(admin);
        mockMissionCtrl = new MockMissionControl();
        vm.stopPrank();
    }

    function deployMissionControlStream() public {
        vm.startPrank(admin);
        missionCtrlStream = new MissionControlStream(host, superToken1, superToken2, address(mockMissionCtrl), "");
        mockMissionCtrl._setMissionControlStream(address(missionCtrlStream));
        vm.stopPrank();
    }

    // helper functions
    function _createPlaceOrder(int256 x, int256 y, int256 z, uint256 tokenId) public pure returns (IMissionControlExtension.PlaceOrder memory) {
        return IMissionControlExtension.PlaceOrder({
            order: IMissionControlExtension.CollectOrder({
                x: x,
                y: y,
                z: z
            }),
            tokenId: tokenId,
            tokenAddress: address(0)
        });
    }

    // is app jailed
    function _checkAppJailed() public returns (bool) {
        assertFalse(host.isAppJailed(missionCtrlStream), "app is jailed");
    }

    function testDeployMissionControleStream() public {
        assertEq(address(missionCtrlStream.acceptedToken1()), address(superToken1));
        assertEq(address(missionCtrlStream.acceptedToken2()), address(superToken2));
        assertEq(address(missionCtrlStream.host()), address(host));
        assertEq(address(missionCtrlStream.missionControl()), address(mockMissionCtrl));
    }

    function testUserRentTiles() public {
        vm.startPrank(alice);
        mockMissionCtrl._setMinFlowRate(100); // 100 wei per second for each tile
        IMissionControlExtension.PlaceOrder[] memory tiles = new IMissionControlExtension.PlaceOrder[](3);
        tiles[0] = _createPlaceOrder(1, 1, 1, 1);
        tiles[1] = _createPlaceOrder(2, 2, 2, 2);
        tiles[2] = _createPlaceOrder(3, 3, 3, 3);
        cfaV1Lib.createFlow(address(missionCtrlStream), superToken1 , 300, abi.encode(tiles));
    }

    function testUserUpdateTilesRemove() public {
        vm.startPrank(alice);
        mockMissionCtrl._setMinFlowRate(100); // 100 wei per second for each tile
        //rent 3 titles
        IMissionControlExtension.PlaceOrder[] memory tiles = new IMissionControlExtension.PlaceOrder[](3);
        tiles[0] = _createPlaceOrder(1, 1, 1, 1);
        tiles[1] = _createPlaceOrder(2, 2, 2, 2);
        tiles[2] = _createPlaceOrder(3, 3, 3, 3);
        cfaV1Lib.createFlow(address(missionCtrlStream), superToken1 , 300, abi.encode(tiles));
        //update to remove 1 tile
        IMissionControlExtension.PlaceOrder[] memory addTiles;
        IMissionControlExtension.CollectOrder[] memory removeTiles = new IMissionControlExtension.CollectOrder[](1);
        removeTiles[0] = IMissionControlExtension.CollectOrder(1, 1, 1);
        cfaV1Lib.updateFlow(address(missionCtrlStream), superToken1 , 200, abi.encode(addTiles, removeTiles));
        _checkAppJailed();
    }

    function testUserUpdateTilesAddAndRemove() public {
        vm.startPrank(alice);
        mockMissionCtrl._setMinFlowRate(100); // 100 wei per second for each tile
        //rent 3 titles
        IMissionControlExtension.PlaceOrder[] memory tiles = new IMissionControlExtension.PlaceOrder[](3);
        tiles[0] = _createPlaceOrder(1, 1, 1, 1);
        tiles[1] = _createPlaceOrder(2, 2, 2, 2);
        tiles[2] = _createPlaceOrder(3, 3, 3, 3);
        cfaV1Lib.createFlow(address(missionCtrlStream), superToken1 , 300, abi.encode(tiles));
        //update to remove 1 tile
        IMissionControlExtension.PlaceOrder[] memory addTiles = new IMissionControlExtension.PlaceOrder[](1);
        addTiles[0] = _createPlaceOrder(4, 4, 4, 4);
        IMissionControlExtension.CollectOrder[] memory removeTiles = new IMissionControlExtension.CollectOrder[](2);
        removeTiles[0] = IMissionControlExtension.CollectOrder(1, 1, 1);
        removeTiles[1] = IMissionControlExtension.CollectOrder(2, 2, 2);
        cfaV1Lib.updateFlow(address(missionCtrlStream), superToken1 , 200, abi.encode(addTiles, removeTiles));
        _checkAppJailed();
    }

    function testUserUpdateTilesWithoutRemove() public {
        vm.startPrank(alice);
        mockMissionCtrl._setMinFlowRate(100); // 100 wei per second for each tile
        //rent 3 titles
        IMissionControlExtension.PlaceOrder[] memory tiles = new IMissionControlExtension.PlaceOrder[](3);
        tiles[0] = _createPlaceOrder(1, 1, 1, 1);
        tiles[1] = _createPlaceOrder(2, 2, 2, 2);
        tiles[2] = _createPlaceOrder(3, 3, 3, 3);
        cfaV1Lib.createFlow(address(missionCtrlStream), superToken1 , 300, abi.encode(tiles));
        //update to remove 1 tile
        IMissionControlExtension.PlaceOrder[] memory addTiles = new IMissionControlExtension.PlaceOrder[](1);
        addTiles[0] = _createPlaceOrder(4, 4, 4, 4);
        IMissionControlExtension.CollectOrder[] memory removeTiles;
        cfaV1Lib.updateFlow(address(missionCtrlStream), superToken1 , 400, abi.encode(addTiles, removeTiles));
        _checkAppJailed();
    }

    function testUserUpdateTilesOnlyRemove() public {
        vm.startPrank(alice);
        mockMissionCtrl._setMinFlowRate(100); // 100 wei per second for each tile
        //rent 3 titles
        IMissionControlExtension.PlaceOrder[] memory tiles = new IMissionControlExtension.PlaceOrder[](3);
        tiles[0] = _createPlaceOrder(1, 1, 1, 1);
        tiles[1] = _createPlaceOrder(2, 2, 2, 2);
        tiles[2] = _createPlaceOrder(3, 3, 3, 3);
        cfaV1Lib.createFlow(address(missionCtrlStream), superToken1 , 300, abi.encode(tiles));
        // mock don't save states between calls but in this case we want to calculate the right flow rate after remove tiles.
        mockMissionCtrl._setTilesCount(3);
        //update to remove 1 tile
        IMissionControlExtension.PlaceOrder[] memory addTiles;
        IMissionControlExtension.CollectOrder[] memory removeTiles = new IMissionControlExtension.CollectOrder[](2);
        removeTiles[0] = IMissionControlExtension.CollectOrder(1, 1, 1);
        removeTiles[1] = IMissionControlExtension.CollectOrder(2, 2, 2);
        cfaV1Lib.updateFlow(address(missionCtrlStream), superToken1 , 200, abi.encode(addTiles, removeTiles));
        mockMissionCtrl._setTilesCount(0);
        _checkAppJailed();
    }

    function testUserUpdateTilesAddAndTerminate() public {
        vm.startPrank(alice);
        mockMissionCtrl._setMinFlowRate(100); // 100 wei per second for each tile
        IMissionControlExtension.PlaceOrder[] memory tiles = new IMissionControlExtension.PlaceOrder[](1);
        tiles[0] = _createPlaceOrder(1, 1, 1, 1);
        cfaV1Lib.createFlow(address(missionCtrlStream), superToken1 , 100, abi.encode(tiles));
        //vm.warp(1000);
        cfaV1Lib.deleteFlow(alice, address(missionCtrlStream) , superToken1);
        _checkAppJailed();
    }

    function testFundControllerCanMoveFunds() public {
        vm.startPrank(alice);
        mockMissionCtrl._setMinFlowRate(100000); // 100 wei per second for each tile
        IMissionControlExtension.PlaceOrder[] memory tiles = new IMissionControlExtension.PlaceOrder[](1);
        tiles[0] = _createPlaceOrder(1, 1, 1, 1);
        cfaV1Lib.createFlow(address(missionCtrlStream), superToken1 , 100000, abi.encode(tiles));
        vm.stopPrank();
        vm.warp(10000);
        vm.prank(admin);
        missionCtrlStream.approve(superToken1, bob, type(uint256).max);
        // bob represent the funds controller. Can be a EOA or a contract with custom logic
        uint256 bobInitialBalance = superToken1.balanceOf(bob);
        vm.prank(bob);
        superToken1.transferFrom(address(missionCtrlStream), bob, 10000000);
        uint256 bobFinalBalance = superToken1.balanceOf(bob);
        assertTrue(bobInitialBalance < bobFinalBalance);
        _checkAppJailed();
    }

    function testUserUpdateTilesAddAndTerminateSecondToken() public {
        vm.startPrank(alice);
        mockMissionCtrl._setMinFlowRate(100); // 100 wei per second for each tile
        IMissionControlExtension.PlaceOrder[] memory tiles = new IMissionControlExtension.PlaceOrder[](1);
        tiles[0] = _createPlaceOrder(1, 1, 1, 1);
        cfaV1Lib.createFlow(address(missionCtrlStream), superToken2 , 100, abi.encode(tiles));
        //vm.warp(1000);
        cfaV1Lib.deleteFlow(alice, address(missionCtrlStream) , superToken2);
        _checkAppJailed();
    }

    function testRevertOnCreate() public
    {
        vm.startPrank(alice);
        mockMissionCtrl._setMinFlowRate(100); // 100 wei per second for each tile
        mockMissionCtrl._setRevertOnCreate(true);
        IMissionControlExtension.PlaceOrder[] memory tiles = new IMissionControlExtension.PlaceOrder[](1);
        tiles[0] = _createPlaceOrder(1, 1, 1, 1);
        vm.expectRevert("MockMissionControl: revertOnCreate");
        cfaV1Lib.createFlow(address(missionCtrlStream), superToken1 , 100, abi.encode(tiles));
        _checkAppJailed();
    }

    function testReverseOnUpdate() public
    {
        vm.startPrank(alice);
        mockMissionCtrl._setMinFlowRate(100); // 100 wei per second for each tile
        mockMissionCtrl._setRevertOnUpdate(true);
        IMissionControlExtension.PlaceOrder[] memory tiles = new IMissionControlExtension.PlaceOrder[](1);
        tiles[0] = _createPlaceOrder(1, 1, 1, 1);
        cfaV1Lib.createFlow(address(missionCtrlStream), superToken1 , 100, abi.encode(tiles));
        vm.expectRevert("MockMissionControl: revertOnUpdate");
        cfaV1Lib.updateFlow(address(missionCtrlStream), superToken1 , 100, abi.encode(tiles, tiles));
        _checkAppJailed();
    }

    function testRevertOnDeleteShouldntJail() public
    {
        vm.startPrank(alice);
        mockMissionCtrl._setMinFlowRate(100); // 100 wei per second for each tile
        mockMissionCtrl._setRevertOnDelete(true);
        IMissionControlExtension.PlaceOrder[] memory tiles = new IMissionControlExtension.PlaceOrder[](1);
        tiles[0] = _createPlaceOrder(1, 1, 1, 1);
        cfaV1Lib.createFlow(address(missionCtrlStream), superToken1 , 100, abi.encode(tiles));
        vm.expectEmit(true, true, true, true);
        emit TerminationCallReverted(alice);
        cfaV1Lib.deleteFlow(alice, address(missionCtrlStream) , superToken1);
        _checkAppJailed();
    }

}