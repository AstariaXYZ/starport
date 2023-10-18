import "starport-test/AstariaV1Test.sol";

import {BaseRecall} from "starport-core/hooks/BaseRecall.sol";
import "forge-std/console2.sol";
import {StarPortLib, Actions} from "starport-core/lib/StarPortLib.sol";

contract TestAstariaV1Loan is AstariaV1Test {
    using {StarPortLib.getId} for LoanManager.Loan;

    function testNewLoanERC721CollateralDefaultTermsRecallBase() public {
        debt.push(SpentItem({itemType: ItemType.ERC20, token: address(erc20s[0]), amount: 100, identifier: 0}));
        StrategistOriginator.Details memory loanDetails = StrategistOriginator.Details({
            conduit: address(lenderConduit),
            custodian: address(custody),
            issuer: lender.addr,
            deadline: block.timestamp + 100,
            offer: StrategistOriginator.Offer({
                salt: bytes32(0),
                terms: terms,
                collateral: ConsiderationItemLib.toSpentItemArray(selectedCollateral),
                debt: debt
            })
        });

        LoanManager.Loan memory loan = newLoan(
            NewLoanData(address(custody), new LoanManager.Caveat[](0), abi.encode(loanDetails)),
            StrategistOriginator(SO),
            selectedCollateral
        );
        uint256 loanId = loan.getId();
        assertTrue(LM.active(loanId), "LoanId not in active state after a new loan");

        {
            vm.startPrank(recaller.addr);
            vm.expectRevert(BaseRecall.RecallBeforeHoneymoonExpiry.selector);
            // attempt recall before honeymoon period has ended
            BaseRecall(address(hook)).recall(loan, recallerConduit);
            vm.stopPrank();
        }
        {
            // refinance with before recall is initiated
            refinanceLoan(
                loan,
                abi.encode(BasePricing.Details({rate: (uint256(1e16) * 100) / (365 * 1 days), carryRate: 0})),
                refinancer.addr,
                abi.encodeWithSelector(Pricing.InvalidRefinance.selector)
            );
        }
        uint256 stake;
        {
            uint256 balanceBefore = erc20s[0].balanceOf(recaller.addr);
            uint256 recallContractBalanceBefore = erc20s[0].balanceOf(address(hook));
            BaseRecall.Details memory details = abi.decode(loan.terms.hookData, (BaseRecall.Details));
            vm.warp(block.timestamp + details.honeymoon);
            vm.startPrank(recaller.addr);

            BaseRecall recallContract = BaseRecall(address(hook));
            recallContract.recall(loan, recallerConduit);
            vm.stopPrank();

            uint256 balanceAfter = erc20s[0].balanceOf(recaller.addr);
            uint256 recallContractBalanceAfter = erc20s[0].balanceOf(address(hook));

            BasePricing.Details memory pricingDetails = abi.decode(loan.terms.pricingData, (BasePricing.Details));
            stake = BasePricing(address(pricing)).calculateInterest(
                details.recallStakeDuration, loan.debt[0].amount, pricingDetails.rate
            );
            assertEq(balanceBefore, balanceAfter + stake, "Recaller balance not transfered correctly");
            assertEq(
                recallContractBalanceBefore + stake,
                recallContractBalanceAfter,
                "Balance not transfered to recall contract correctly"
            );
        }
        {
            BaseRecall recallContract = BaseRecall(address(hook));
            address recallerAddr;
            uint64 start;
            (recallerAddr, start) = recallContract.recalls(loanId);

            assertEq(recaller.addr, recallerAddr, "Recaller address logged incorrectly");
            assertEq(start, block.timestamp, "Recall start logged incorrectly");
        }
        {
            BaseRecall recallContract = BaseRecall(address(hook));
            vm.expectRevert(BaseRecall.LoanHasNotBeenRefinanced.selector);
            // attempt a withdraw without the loan being refinanced
            recallContract.withdraw(loan, payable(address(this)));
        }
        {
            // refinance with incorrect terms
            refinanceLoan(
                loan,
                abi.encode(BasePricing.Details({rate: (uint256(1e16) * 100) / (365 * 1 days), carryRate: 0})),
                refinancer.addr,
                abi.encodeWithSelector(AstariaV1Pricing.InsufficientRefinance.selector)
            );
        }
        {
            // refinance with correct terms
            uint256 newLenderBefore = erc20s[0].balanceOf(refinancer.addr);
            uint256 oldLenderBefore = erc20s[0].balanceOf(lender.addr);
            uint256 recallerBefore = erc20s[0].balanceOf(recaller.addr);
            BaseRecall.Details memory details = abi.decode(loan.terms.hookData, (BaseRecall.Details));
            vm.warp(block.timestamp + (details.recallWindow / 2));
            refinanceLoan(
                loan, abi.encode(BasePricing.Details({rate: details.recallMax / 2, carryRate: 0})), refinancer.addr
            );
            uint256 delta_t = block.timestamp - loan.start;
            BasePricing.Details memory pricingDetails = abi.decode(loan.terms.pricingData, (BasePricing.Details));
            uint256 interest =
                BasePricing(address(pricing)).calculateInterest(delta_t, loan.debt[0].amount, pricingDetails.rate);
            uint256 newLenderAfter = erc20s[0].balanceOf(refinancer.addr);
            uint256 oldLenderAfter = erc20s[0].balanceOf(lender.addr);
            assertEq(
                oldLenderAfter,
                oldLenderBefore + loan.debt[0].amount + interest,
                "Payment to old lender calculated incorrectly"
            );
            assertEq(
                newLenderAfter,
                newLenderBefore - (loan.debt[0].amount + interest + stake),
                "Payment from new lender calculated incorrectly"
            );
            assertEq(
                recallerBefore + stake, erc20s[0].balanceOf(recaller.addr), "Recaller did not recover stake as expected"
            );
            assertTrue(LM.inactive(loanId), "LoanId not properly flipped to inactive after refinance");
        }
        {
            uint256 withdrawerBalanceBefore = erc20s[0].balanceOf(address(this));
            uint256 recallContractBalanceBefore = erc20s[0].balanceOf(address(hook));
            BaseRecall recallContract = BaseRecall(address(hook));

            // attempt a withdraw after the loan has been successfully refinanced
            recallContract.withdraw(loan, payable(address(this)));
            uint256 withdrawerBalanceAfter = erc20s[0].balanceOf(address(this));
            uint256 recallContractBalanceAfter = erc20s[0].balanceOf(address(hook));
            assertEq(
                withdrawerBalanceBefore + stake, withdrawerBalanceAfter, "Withdrawer did not recover stake as expected"
            );
            assertEq(
                recallContractBalanceBefore - stake,
                recallContractBalanceAfter,
                "BaseRecall did not return the stake as expected"
            );
        }
    }

    // lender is recaller, liquidation amount is 0
    function testNewLoanERC721CollateralDefaultTermsRecallLender() public {
        Custodian custody = Custodian(LM.defaultCustodian());

        LoanManager.Terms memory terms = LoanManager.Terms({
            hook: address(hook),
            handler: address(handler),
            pricing: address(pricing),
            pricingData: defaultPricingData,
            handlerData: defaultHandlerData,
            hookData: defaultHookData
        });

        selectedCollateral.push(
            ConsiderationItem({
                token: address(erc721s[0]),
                startAmount: 1,
                endAmount: 1,
                identifierOrCriteria: 1,
                itemType: ItemType.ERC721,
                recipient: payable(address(custody))
            })
        );

        debt.push(SpentItem({itemType: ItemType.ERC20, token: address(erc20s[0]), amount: 100, identifier: 0}));
        StrategistOriginator.Details memory loanDetails = StrategistOriginator.Details({
            conduit: address(lenderConduit),
            custodian: address(custody),
            issuer: lender.addr,
            deadline: block.timestamp + 100,
            offer: StrategistOriginator.Offer({
                salt: bytes32(0),
                terms: terms,
                collateral: ConsiderationItemLib.toSpentItemArray(selectedCollateral),
                debt: debt
            })
        });

        LoanManager.Loan memory loan = newLoan(
            NewLoanData(address(custody), new LoanManager.Caveat[](0), abi.encode(loanDetails)),
            StrategistOriginator(SO),
            selectedCollateral
        );
        uint256 loanId = loan.getId();

        uint256 stake;
        {
            uint256 balanceBefore = erc20s[0].balanceOf(lender.addr);
            uint256 recallContractBalanceBefore = erc20s[0].balanceOf(address(hook));
            BaseRecall.Details memory details = abi.decode(loan.terms.hookData, (BaseRecall.Details));
            vm.warp(block.timestamp + details.honeymoon);
            vm.startPrank(lender.addr);
            conduitController.updateChannel(lenderConduit, address(hook), true);
            BaseRecall recallContract = BaseRecall(address(hook));
            recallContract.recall(loan, lenderConduit);
            vm.stopPrank();

            uint256 balanceAfter = erc20s[0].balanceOf(lender.addr);
            uint256 recallContractBalanceAfter = erc20s[0].balanceOf(address(hook));

            BasePricing.Details memory pricingDetails = abi.decode(loan.terms.pricingData, (BasePricing.Details));
            stake = BasePricing(address(pricing)).calculateInterest(
                details.recallStakeDuration, loan.debt[0].amount, pricingDetails.rate
            );
            assertEq(balanceBefore, balanceAfter + stake, "Recaller balance not transfered correctly");
            assertEq(
                recallContractBalanceBefore + stake,
                recallContractBalanceAfter,
                "Balance not transfered to recall contract correctly"
            );
        }

        {
            BaseRecall.Details memory details = abi.decode(loan.terms.hookData, (BaseRecall.Details));
            // warp past the end of the recall window
            vm.warp(block.timestamp + details.recallWindow + 1);

            OfferItem[] memory repayOffering = new OfferItem[](
            loan.collateral.length
          );
            uint256 i = 0;
            for (; i < loan.collateral.length;) {
                repayOffering[i] = OfferItem({
                    itemType: loan.collateral[i].itemType,
                    token: address(loan.collateral[i].token),
                    identifierOrCriteria: loan.collateral[i].identifier,
                    endAmount: loan.collateral[i].itemType != ItemType.ERC721 ? loan.collateral[i].amount : 1,
                    startAmount: loan.collateral[i].itemType != ItemType.ERC721 ? loan.collateral[i].amount : 1
                });
                unchecked {
                    ++i;
                }
            }
            (ReceivedItem[] memory settlementConsideration, address restricted) =
                SettlementHandler(loan.terms.handler).getSettlement(loan);

            assertEq(
                settlementConsideration.length, 0, "Settlement consideration for a recalling Lender should be zero"
            );
            assertEq(restricted, lender.addr, "SettlementConsideration should be restricted to the lender");
            ConsiderationItem[] memory consider = new ConsiderationItem[](
            settlementConsideration.length
          );
            i = 0;
            for (; i < settlementConsideration.length;) {
                consider[i].token = settlementConsideration[i].token;
                consider[i].itemType = settlementConsideration[i].itemType;
                consider[i].identifierOrCriteria = settlementConsideration[i].identifier;
                consider[i].startAmount = settlementConsideration[i].amount;
                consider[i].endAmount = settlementConsideration[i].amount;
                consider[i].recipient = settlementConsideration[i].recipient;
                unchecked {
                    ++i;
                }
            }

            vm.startPrank(lender.addr);
            OrderParameters memory op = _buildContractOrder(address(loan.custodian), repayOffering, consider);

            AdvancedOrder memory settlementOrder = AdvancedOrder({
                numerator: 1,
                denominator: 1,
                parameters: op,
                extraData: abi.encode(Actions.Settlement, loan),
                signature: ""
            });

            consideration.fulfillAdvancedOrder({
                advancedOrder: settlementOrder,
                criteriaResolvers: new CriteriaResolver[](0),
                fulfillerConduitKey: bytes32(0),
                recipient: address(0)
            });
            vm.stopPrank();
        }
        {
            address owner = erc721s[0].ownerOf(1);
            assertEq(owner, lender.addr, "Lender should be the owner of the NFT after settlement");
        }
    }

    // recaller is not the lender, liquidation amount is a dutch auction
    function testNewLoanERC721CollateralDefaultTermsRecallLiquidation() public {
        Custodian custody = Custodian(LM.defaultCustodian());

        LoanManager.Terms memory terms = LoanManager.Terms({
            hook: address(hook),
            handler: address(handler),
            pricing: address(pricing),
            pricingData: defaultPricingData,
            handlerData: defaultHandlerData,
            hookData: defaultHookData
        });

        selectedCollateral.push(
            ConsiderationItem({
                token: address(erc721s[0]),
                startAmount: 1,
                endAmount: 1,
                identifierOrCriteria: 1,
                itemType: ItemType.ERC721,
                recipient: payable(address(custody))
            })
        );

        debt.push(SpentItem({itemType: ItemType.ERC20, token: address(erc20s[0]), amount: 100, identifier: 0}));
        StrategistOriginator.Details memory loanDetails = StrategistOriginator.Details({
            conduit: address(lenderConduit),
            custodian: address(custody),
            issuer: lender.addr,
            deadline: block.timestamp + 100,
            offer: StrategistOriginator.Offer({
                salt: bytes32(0),
                terms: terms,
                collateral: ConsiderationItemLib.toSpentItemArray(selectedCollateral),
                debt: debt
            })
        });

        LoanManager.Loan memory loan = newLoan(
            NewLoanData(address(custody), new LoanManager.Caveat[](0), abi.encode(loanDetails)),
            StrategistOriginator(SO),
            selectedCollateral
        );
        uint256 loanId = loan.getId();

        uint256 stake;
        {
            uint256 balanceBefore = erc20s[0].balanceOf(recaller.addr);
            uint256 recallContractBalanceBefore = erc20s[0].balanceOf(address(hook));
            BaseRecall.Details memory details = abi.decode(loan.terms.hookData, (BaseRecall.Details));
            vm.warp(block.timestamp + details.honeymoon);
            vm.startPrank(recaller.addr);

            BaseRecall recallContract = BaseRecall(address(hook));
            recallContract.recall(loan, recallerConduit);
            vm.stopPrank();

            uint256 balanceAfter = erc20s[0].balanceOf(recaller.addr);
            uint256 recallContractBalanceAfter = erc20s[0].balanceOf(address(hook));

            BasePricing.Details memory pricingDetails = abi.decode(loan.terms.pricingData, (BasePricing.Details));
            stake = BasePricing(address(pricing)).calculateInterest(
                details.recallStakeDuration, loan.debt[0].amount, pricingDetails.rate
            );
            assertEq(balanceBefore, balanceAfter + stake, "Recaller balance not transfered correctly");
            assertEq(
                recallContractBalanceBefore + stake,
                recallContractBalanceAfter,
                "Balance not transfered to recall contract correctly"
            );
        }

        {
            BaseRecall.Details memory details = abi.decode(loan.terms.hookData, (BaseRecall.Details));
            // warp past the end of the recall window
            vm.warp(block.timestamp + details.recallWindow + 1);

            OfferItem[] memory repayOffering = new OfferItem[](
                loan.collateral.length
            );
            uint256 i = 0;
            for (; i < loan.collateral.length;) {
                repayOffering[i] = OfferItem({
                    itemType: loan.collateral[i].itemType,
                    token: address(loan.collateral[i].token),
                    identifierOrCriteria: loan.collateral[i].identifier,
                    endAmount: loan.collateral[i].itemType != ItemType.ERC721 ? loan.collateral[i].amount : 1,
                    startAmount: loan.collateral[i].itemType != ItemType.ERC721 ? loan.collateral[i].amount : 1
                });
                unchecked {
                    ++i;
                }
            }
            (ReceivedItem[] memory settlementConsideration, address restricted) =
                SettlementHandler(loan.terms.handler).getSettlement(loan);

            assertEq(
                settlementConsideration.length, 2, "Settlement consideration length for a dutch auction should be 2"
            );
            assertEq(restricted, address(0), "SettlementConsideration should be unrestricted");
            assertEq(settlementConsideration[0].amount, 450 ether, "Settlement consideration for loan incorrect");
            assertEq(settlementConsideration[1].amount, 50 ether, "Settlement consideration for loan incorrect");
            ConsiderationItem[] memory consider = new ConsiderationItem[](
                settlementConsideration.length
            );
            i = 0;
            for (; i < settlementConsideration.length;) {
                consider[i].token = settlementConsideration[i].token;
                consider[i].itemType = settlementConsideration[i].itemType;
                consider[i].identifierOrCriteria = settlementConsideration[i].identifier;
                consider[i].startAmount = settlementConsideration[i].amount;
                consider[i].endAmount = settlementConsideration[i].amount;
                consider[i].recipient = settlementConsideration[i].recipient;
                unchecked {
                    ++i;
                }
            }

            uint256 balanceBefore = erc20s[0].balanceOf(address(this));
            OrderParameters memory op = _buildContractOrder(address(loan.custodian), repayOffering, consider);

            AdvancedOrder memory settlementOrder = AdvancedOrder({
                numerator: 1,
                denominator: 1,
                parameters: op,
                extraData: abi.encode(Actions.Settlement, loan),
                signature: ""
            });

            consideration.fulfillAdvancedOrder({
                advancedOrder: settlementOrder,
                criteriaResolvers: new CriteriaResolver[](0),
                fulfillerConduitKey: bytes32(0),
                recipient: address(0)
            });
            uint256 balanceAfter = erc20s[0].balanceOf(address(this));
            address owner = erc721s[0].ownerOf(1);
            assertEq(balanceBefore - 500 ether, balanceAfter, "balance of buyer not decremented correctly");
            assertEq(owner, address(this), "Test address should be the owner of the NFT after settlement");
        }
    }
}
