pragma solidity ^0.8.0;

import "forge-std/Console.sol";
import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import { SuperfluidFrameworkDeployer, SuperfluidTester, Superfluid, ConstantFlowAgreementV1, CFAv1Library } from "./utils/SuperfluidTester.sol";
import { ERC1820RegistryCompiled } from "@superfluid-finance/ethereum-contracts/contracts/libs/ERC1820RegistryCompiled.sol";
import { IMissionControl, MissionControlStream } from "./../src/MissionControlStream.sol";
import { MockMissionControl } from "./mocks/MockMissionControl.sol";

contract MissionControlTest is SuperfluidTester {

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

    function testDeployMissionControleStream() public {
        assertEq(address(missionCtrlStream.acceptedToken1()), address(superToken1));
        assertEq(address(missionCtrlStream.acceptedToken2()), address(superToken2));
        assertEq(address(missionCtrlStream.host()), address(host));
        assertEq(address(missionCtrlStream.missionControl()), address(mockMissionCtrl));
    }

    function testUserRentTiles() public {
        vm.startPrank(alice);
        mockMissionCtrl._setMinFlowRate(100); // 100 wei per second for each tile
        IMissionControl.PlaceOrder[] memory tiles = new IMissionControl.PlaceOrder[](3);
        tiles[0] = IMissionControl.PlaceOrder(1, 1, 1, 1, address(0));
        tiles[1] = IMissionControl.PlaceOrder(2, 2, 2, 2, address(0));
        tiles[2] = IMissionControl.PlaceOrder(3, 3, 3, 3, address(0));
        cfaV1Lib.createFlow(address(missionCtrlStream), superToken1 , 300, abi.encode(tiles));
    }

    function testUserUpdateTilesRemove() public {
        vm.startPrank(alice);
        mockMissionCtrl._setMinFlowRate(100); // 100 wei per second for each tile
        //rent 3 titles
        IMissionControl.PlaceOrder[] memory tiles = new IMissionControl.PlaceOrder[](3);
        tiles[0] = IMissionControl.PlaceOrder(1, 1, 1, 1, address(0));
        tiles[1] = IMissionControl.PlaceOrder(2, 2, 2, 2, address(0));
        tiles[2] = IMissionControl.PlaceOrder(3, 3, 3, 3, address(0));
        cfaV1Lib.createFlow(address(missionCtrlStream), superToken1 , 300, abi.encode(tiles));
        //vm.warp(1000);
        //update to remove 1 tile
        IMissionControl.PlaceOrder[] memory addTiles;
        IMissionControl.PlaceOrder[] memory removeTiles = new IMissionControl.PlaceOrder[](1);
        removeTiles[0] = IMissionControl.PlaceOrder(1, 1, 1, 1, address(0));
        cfaV1Lib.updateFlow(address(missionCtrlStream), superToken1 , 200, abi.encode(addTiles, removeTiles));
    }

    function testUserUpdateTilesAddAndRemove() public {
        vm.startPrank(alice);
        mockMissionCtrl._setMinFlowRate(100); // 100 wei per second for each tile
        //rent 3 titles
        IMissionControl.PlaceOrder[] memory tiles = new IMissionControl.PlaceOrder[](3);
        tiles[0] = IMissionControl.PlaceOrder(1, 1, 1, 1, address(0));
        tiles[1] = IMissionControl.PlaceOrder(2, 2, 2, 2, address(0));
        tiles[2] = IMissionControl.PlaceOrder(3, 3, 3, 3, address(0));
        cfaV1Lib.createFlow(address(missionCtrlStream), superToken1 , 300, abi.encode(tiles));
        //vm.warp(1000);
        //update to remove 1 tile
        IMissionControl.PlaceOrder[] memory addTiles = new IMissionControl.PlaceOrder[](1);
        addTiles[0] = IMissionControl.PlaceOrder(4, 4, 4, 4, address(0));
        IMissionControl.PlaceOrder[] memory removeTiles = new IMissionControl.PlaceOrder[](2);
        removeTiles[0] = IMissionControl.PlaceOrder(1, 1, 1, 1, address(0));
        removeTiles[1] = IMissionControl.PlaceOrder(2, 2, 2, 2, address(0));
        cfaV1Lib.updateFlow(address(missionCtrlStream), superToken1 , 200, abi.encode(addTiles, removeTiles));
    }

    function testUserUpdateTilesAddAndTerminate() public {
        vm.startPrank(alice);
        mockMissionCtrl._setMinFlowRate(100); // 100 wei per second for each tile
        IMissionControl.PlaceOrder[] memory tiles = new IMissionControl.PlaceOrder[](1);
        tiles[0] = IMissionControl.PlaceOrder(1, 1, 1, 1, address(0));
        cfaV1Lib.createFlow(address(missionCtrlStream), superToken1 , 100, abi.encode(tiles));
        //vm.warp(1000);
        cfaV1Lib.deleteFlow(alice, address(missionCtrlStream) , superToken1);
    }

    function testFundControllerCanMoveFunds() public {
        vm.startPrank(alice);
        mockMissionCtrl._setMinFlowRate(100000); // 100 wei per second for each tile
        IMissionControl.PlaceOrder[] memory tiles = new IMissionControl.PlaceOrder[](1);
        tiles[0] = IMissionControl.PlaceOrder(1, 1, 1, 1, address(0));
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
    }

    function testUserUpdateTilesAddAndTerminateSecondToken() public {
        vm.startPrank(alice);
        mockMissionCtrl._setMinFlowRate(100); // 100 wei per second for each tile
        IMissionControl.PlaceOrder[] memory tiles = new IMissionControl.PlaceOrder[](1);
        tiles[0] = IMissionControl.PlaceOrder(1, 1, 1, 1, address(0));
        cfaV1Lib.createFlow(address(missionCtrlStream), superToken2 , 100, abi.encode(tiles));
        //vm.warp(1000);
        cfaV1Lib.deleteFlow(alice, address(missionCtrlStream) , superToken2);
    }
}