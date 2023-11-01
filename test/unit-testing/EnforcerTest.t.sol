pragma solidity ^0.8.17;

import "starport-test/StarPortTest.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {LibString} from "solady/src/utils/LibString.sol";

import "forge-std/console.sol";

contract EnforcerTest is StarPortTest {
//     function testTermEnforcerBasic() public {
//         LoanManager.Terms memory terms = LoanManager.Terms({
//             hook: address(hook),
//             handler: address(handler),
//             pricing: address(pricing),
//             pricingData: defaultPricingData,
//             handlerData: defaultHandlerData,
//             hookData: defaultHookData
//         });

//         uint256 initial721Balance = erc721s[0].balanceOf(borrower.addr);
//         assertTrue(initial721Balance > 0, "Test must have at least one erc721 token");

//         uint256 initial20Balance = erc20s[0].balanceOf(borrower.addr);

//         TermEnforcer TE = new TermEnforcer();

//         TermEnforcer.Details memory TEDetails =
//             TermEnforcer.Details({pricing: address(pricing), hook: address(hook), handler: address(handler)});

//         LoanManager.Caveat[] memory caveats = new LoanManager.Caveat[](1);
//         caveats[0] = LoanManager.Caveat({enforcer: address(TE), terms: abi.encode(TEDetails)});

//         LoanManager.Loan memory loan = _createLoanWithCaveat({
//             lender: lender.addr,
//             terms: terms,
//             collateralItem: ConsiderationItem({
//                 token: address(erc721s[0]),
//                 startAmount: 1,
//                 endAmount: 1,
//                 identifierOrCriteria: 1,
//                 itemType: ItemType.ERC721,
//                 recipient: payable(address(custodian))
//             }),
//             debtItem: SpentItem({itemType: ItemType.ERC20, token: address(erc20s[0]), amount: 100, identifier: 0}),
//             caveats: caveats
//         });

//         //        LoanManager.Loan memory loan =
//         //            _createLoan721Collateral20Debt({lender: lender.addr, borrowAmount: 100, terms: terms});
//         //
//         //        assertTrue(erc721s[0].balanceOf(borrower.addr) < initial721Balance, "Borrower ERC721 was not sent out");
//         //        assertTrue(erc20s[0].balanceOf(borrower.addr) > initial20Balance, "Borrower did not receive ERC20");
//         //
//         //        uint256 loanId = loan.getId();
//         //        assertTrue(LM.active(loanId), "LoanId not in active state after a new loan");
//         //        skip(10 days);
//         //
//         //        _repayLoan({borrower: borrower.addr, amount: 375, loan: loan});
//     }

//     function testRateEnforcerBasic() public {
//         LoanManager.Terms memory terms = LoanManager.Terms({
//             hook: address(hook),
//             handler: address(handler),
//             pricing: address(pricing),
//             pricingData: defaultPricingData,
//             handlerData: defaultHandlerData,
//             hookData: defaultHookData
//         });

//         uint256 initial721Balance = erc721s[0].balanceOf(borrower.addr);
//         assertTrue(initial721Balance > 0, "Test must have at least one erc721 token");

//         uint256 initial20Balance = erc20s[0].balanceOf(borrower.addr);

//         FixedRateEnforcer RE = new FixedRateEnforcer();

//         FixedRateEnforcer.Details memory REDetails = FixedRateEnforcer.Details({
//             maxRate: ((uint256(1e16) * 150) / (365 * 1 days)) * 2,
//             maxCarryRate: (uint256(1e16) * 10) * 2
//         });

//         LoanManager.Caveat[] memory caveats = new LoanManager.Caveat[](1);
//         caveats[0] = LoanManager.Caveat({enforcer: address(RE), terms: abi.encode(REDetails)});

//         LoanManager.Loan memory loan = _createLoanWithCaveat({
//             lender: lender.addr,
//             terms: terms,
//             collateralItem: ConsiderationItem({
//                 token: address(erc721s[0]),
//                 startAmount: 1,
//                 endAmount: 1,
//                 identifierOrCriteria: 1,
//                 itemType: ItemType.ERC721,
//                 recipient: payable(address(custodian))
//             }),
//             debtItem: SpentItem({itemType: ItemType.ERC20, token: address(erc20s[0]), amount: 100, identifier: 0}),
//             caveats: caveats
//         });
//     }

//     function testFailRateEnforcerMaxRate() public {
//         LoanManager.Terms memory terms = LoanManager.Terms({
//             hook: address(hook),
//             handler: address(handler),
//             pricing: address(pricing),
//             pricingData: defaultPricingData,
//             handlerData: defaultHandlerData,
//             hookData: defaultHookData
//         });

//         uint256 initial721Balance = erc721s[0].balanceOf(borrower.addr);
//         assertTrue(initial721Balance > 0, "Test must have at least one erc721 token");

//         uint256 initial20Balance = erc20s[0].balanceOf(borrower.addr);

//         FixedRateEnforcer RE = new FixedRateEnforcer();

//         FixedRateEnforcer.Details memory REDetails = FixedRateEnforcer.Details({
//             maxRate: (uint256(1e16) * 150) / (365 * 1 days),
//             maxCarryRate: (uint256(1e16) * 10) * 2
//         }); // maxRate == defaultPricingData.carryRate

//         LoanManager.Caveat[] memory caveats = new LoanManager.Caveat[](1);
//         caveats[0] = LoanManager.Caveat({enforcer: address(RE), terms: abi.encode(REDetails)});

//         LoanManager.Loan memory loan = _createLoanWithCaveat({
//             lender: lender.addr,
//             terms: terms,
//             collateralItem: ConsiderationItem({
//                 token: address(erc721s[0]),
//                 startAmount: 1,
//                 endAmount: 1,
//                 identifierOrCriteria: 1,
//                 itemType: ItemType.ERC721,
//                 recipient: payable(address(custodian))
//             }),
//             debtItem: SpentItem({itemType: ItemType.ERC20, token: address(erc20s[0]), amount: 100, identifier: 0}),
//             caveats: caveats
//         });
//     }

//     function testFailRateEnforcerMaxCarryRate() public {
//         LoanManager.Terms memory terms = LoanManager.Terms({
//             hook: address(hook),
//             handler: address(handler),
//             pricing: address(pricing),
//             pricingData: defaultPricingData,
//             handlerData: defaultHandlerData,
//             hookData: defaultHookData
//         });

//         uint256 initial721Balance = erc721s[0].balanceOf(borrower.addr);
//         assertTrue(initial721Balance > 0, "Test must have at least one erc721 token");

//         uint256 initial20Balance = erc20s[0].balanceOf(borrower.addr);

//         FixedRateEnforcer RE = new FixedRateEnforcer();

//         FixedRateEnforcer.Details memory REDetails = FixedRateEnforcer.Details({
//             maxRate: ((uint256(1e16) * 150) / (365 * 1 days)) * 2,
//             maxCarryRate: (uint256(1e16) * 10)
//         }); // maxCarryRate == defaultPricingData.rate

//         LoanManager.Caveat[] memory caveats = new LoanManager.Caveat[](1);
//         caveats[0] = LoanManager.Caveat({enforcer: address(RE), terms: abi.encode(REDetails)});

//         LoanManager.Loan memory loan = _createLoanWithCaveat({
//             lender: lender.addr,
//             terms: terms,
//             collateralItem: ConsiderationItem({
//                 token: address(erc721s[0]),
//                 startAmount: 1,
//                 endAmount: 1,
//                 identifierOrCriteria: 1,
//                 itemType: ItemType.ERC721,
//                 recipient: payable(address(custodian))
//             }),
//             debtItem: SpentItem({itemType: ItemType.ERC20, token: address(erc20s[0]), amount: 100, identifier: 0}),
//             caveats: caveats
//         });
//     }

//     function testFailRateEnforcerMaxRateAndMaxCarryRate() public {
//         LoanManager.Terms memory terms = LoanManager.Terms({
//             hook: address(hook),
//             handler: address(handler),
//             pricing: address(pricing),
//             pricingData: defaultPricingData,
//             handlerData: defaultHandlerData,
//             hookData: defaultHookData
//         });

//         uint256 initial721Balance = erc721s[0].balanceOf(borrower.addr);
//         assertTrue(initial721Balance > 0, "Test must have at least one erc721 token");

//         uint256 initial20Balance = erc20s[0].balanceOf(borrower.addr);

//         FixedRateEnforcer RE = new FixedRateEnforcer();

//         FixedRateEnforcer.Details memory REDetails = FixedRateEnforcer.Details({
//             maxRate: (uint256(1e16) * 150) / (365 * 1 days),
//             maxCarryRate: (uint256(1e16) * 10)
//         }); // maxCarryRate == defaultPricingData.rate

//         LoanManager.Caveat[] memory caveats = new LoanManager.Caveat[](1);
//         caveats[0] = LoanManager.Caveat({enforcer: address(RE), terms: abi.encode(REDetails)});

//         LoanManager.Loan memory loan = _createLoanWithCaveat({
//             lender: lender.addr,
//             terms: terms,
//             collateralItem: ConsiderationItem({
//                 token: address(erc721s[0]),
//                 startAmount: 1,
//                 endAmount: 1,
//                 identifierOrCriteria: 1,
//                 itemType: ItemType.ERC721,
//                 recipient: payable(address(custodian))
//             }),
//             debtItem: SpentItem({itemType: ItemType.ERC20, token: address(erc20s[0]), amount: 100, identifier: 0}),
//             caveats: caveats
//         });
//     }

//     function testCollateralEnforcer() public {
//         LoanManager.Terms memory terms = LoanManager.Terms({
//             hook: address(hook),
//             handler: address(handler),
//             pricing: address(pricing),
//             pricingData: defaultPricingData,
//             handlerData: defaultHandlerData,
//             hookData: defaultHookData
//         });

//         uint256 initial721Balance = erc721s[0].balanceOf(borrower.addr);
//         assertTrue(initial721Balance > 0, "Test must have at least one erc721 token");

//         uint256 initial20Balance = erc20s[0].balanceOf(borrower.addr);

//         CollateralEnforcer CE = new CollateralEnforcer();

//         SpentItem[] memory CECollateral = new SpentItem[](1);

//         CECollateral[0] = SpentItem({itemType: ItemType.ERC721, token: address(erc721s[0]), amount: 1, identifier: 1});

//         CollateralEnforcer.Details memory CEDetails =
//             CollateralEnforcer.Details({collateral: CECollateral, isAny: true});

//         LoanManager.Caveat[] memory caveats = new LoanManager.Caveat[](1);
//         caveats[0] = LoanManager.Caveat({enforcer: address(CE), terms: abi.encode(CEDetails)});

//         LoanManager.Loan memory loan = _createLoanWithCaveat({
//             lender: lender.addr,
//             terms: terms,
//             collateralItem: ConsiderationItem({
//                 token: address(erc721s[0]),
//                 startAmount: 1,
//                 endAmount: 1,
//                 identifierOrCriteria: 1,
//                 itemType: ItemType.ERC721,
//                 recipient: payable(address(custodian))
//             }),
//             debtItem: SpentItem({itemType: ItemType.ERC20, token: address(erc20s[0]), amount: 100, identifier: 0}),
//             caveats: caveats
//         });
//     }

//     function testFailCollateralEnforcerDifferentCollateral() public {
//         LoanManager.Terms memory terms = LoanManager.Terms({
//             hook: address(hook),
//             handler: address(handler),
//             pricing: address(pricing),
//             pricingData: defaultPricingData,
//             handlerData: defaultHandlerData,
//             hookData: defaultHookData
//         });

//         uint256 initial721Balance = erc721s[0].balanceOf(borrower.addr);
//         assertTrue(initial721Balance > 0, "Test must have at least one erc721 token");

//         uint256 initial20Balance = erc20s[0].balanceOf(borrower.addr);

//         CollateralEnforcer CE = new CollateralEnforcer();

//         SpentItem[] memory CECollateral = new SpentItem[](1);

//         CECollateral[0] = SpentItem({itemType: ItemType.ERC721, token: address(erc721s[1]), amount: 1, identifier: 1});

//         CollateralEnforcer.Details memory CEDetails =
//             CollateralEnforcer.Details({collateral: CECollateral, isAny: true});

//         LoanManager.Caveat[] memory caveats = new LoanManager.Caveat[](1);
//         caveats[0] = LoanManager.Caveat({enforcer: address(CE), terms: abi.encode(CEDetails)});

//         LoanManager.Loan memory loan = _createLoanWithCaveat({
//             lender: lender.addr,
//             terms: terms,
//             collateralItem: ConsiderationItem({
//                 token: address(erc721s[0]),
//                 startAmount: 1,
//                 endAmount: 1,
//                 identifierOrCriteria: 1,
//                 itemType: ItemType.ERC721,
//                 recipient: payable(address(custodian))
//             }),
//             debtItem: SpentItem({itemType: ItemType.ERC20, token: address(erc20s[0]), amount: 100, identifier: 0}),
//             caveats: caveats
//         });
//     }
}
