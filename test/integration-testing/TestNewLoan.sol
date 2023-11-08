pragma solidity ^0.8.17;

import "starport-test/StarportTest.sol";
import {StarportLib, Actions} from "starport-core/lib/StarportLib.sol";
import {BNPLHelper, IFlashLoanRecipient} from "starport-core/BNPLHelper.sol";
import {Originator} from "starport-core/originators/Originator.sol";

contract FlashLoan {
    function flashLoan(
        IFlashLoanRecipient recipient,
        address[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external {
        uint256[] memory feeAmounts = new uint256[](tokens.length);
        uint256[] memory preLoanBalances = new uint256[](tokens.length);

        // Used to ensure `tokens` is sorted in ascending order, which ensures token uniqueness.
        ERC20 previousToken = ERC20(address(0));

        for (uint256 i = 0; i < tokens.length; ++i) {
            ERC20 token = ERC20(tokens[i]);
            uint256 amount = amounts[i];

            //            previousToken = token;

            preLoanBalances[i] = token.balanceOf(address(this));
            feeAmounts[i] = uint256(0);

            token.transfer(address(recipient), amount);
        }

        recipient.receiveFlashLoan(tokens, amounts, feeAmounts, userData);

        for (uint256 i = 0; i < tokens.length; ++i) {
            ERC20 token = ERC20(tokens[i]);
            uint256 preLoanBalance = preLoanBalances[i];

            // Checking for loan repayment first (without accounting for fees) makes for simpler debugging, and results
            // in more accurate revert reasons if the flash loan protocol fee percentage is zero.
            uint256 postLoanBalance = token.balanceOf(address(this));
            require(postLoanBalance >= preLoanBalance, "loan was not paid back");

            // No need for checked arithmetic since we know the loan was fully repaid.
            uint256 receivedFeeAmount = postLoanBalance - preLoanBalance;
            require(receivedFeeAmount >= feeAmounts[i], "no fees paid");

            //            _payFeeAmount(token, receivedFeeAmount);
            //            emit FlashLoan(recipient, token, amounts[i], receivedFeeAmount);
        }
    }
}

contract TestNewLoan is StarportTest {
    function testNewLoanERC721CollateralDefaultTerms2() public returns (Starport.Loan memory) {
        Custodian custody = Custodian(SP.defaultCustodian());

        Starport.Terms memory terms = Starport.Terms({
            status: address(status),
            settlement: address(settlement),
            pricing: address(pricing),
            pricingData: defaultPricingData,
            settlementData: defaultSettlementData,
            statusData: defaultStatusData
        });

        return _createLoan721Collateral20Debt({lender: lender.addr, borrowAmount: 100, terms: terms});
    }

    function testNewLoanERC721CollateralLessDebtThanOffered() public returns (Starport.Loan memory) {
        // Custodian custody = Custodian(SP.defaultCustodian());

        // Starport.Terms memory terms = Starport.Terms({
        //     status: address(hook),
        //     settlement: address(settlement),
        //     pricing: address(pricing),
        //     pricingData: defaultPricingData,
        //     settlementData: defaultSettlementData,
        //     statusData: defaultStatusData
        // });

        // selectedCollateral.push(
        //     ConsiderationItem({
        //         token: address(erc721s[0]),
        //         startAmount: 1,
        //         endAmount: 1,
        //         identifierOrCriteria: 1,
        //         itemType: ItemType.ERC721,
        //         recipient: payable(address(custody))
        //     })
        // );

        // debt.push(SpentItem({itemType: ItemType.ERC20, token: address(erc20s[0]), amount: 100, identifier: 0}));
        // StrategistOriginator.Details memory loanDetails = StrategistOriginator.Details({
        //     conduit: address(lenderConduit),
        //     custodian: address(custody),
        //     issuer: lender.addr,
        //     deadline: block.timestamp + 100,
        //     offer: StrategistOriginator.Offer({
        //         salt: bytes32(0),
        //         terms: terms,
        //         collateral: ConsiderationItemLib.toSpentItemArray(selectedCollateral),
        //         debt: debt
        //     })
        // });
        // debt[0].amount = 50;

        // TermEnforcer TE = new TermEnforcer();

        // TermEnforcer.Details memory TEDetails =
        //     TermEnforcer.Details({pricing: address(pricing), status: address(hook), settlement: address(settlement)});

        // Starport.Caveat[] memory caveats = new Starport.Caveat[](1);
        // caveats[0] = Starport.Caveat({enforcer: address(TE), terms: abi.encode(TEDetails)});

        // return newLoan(
        //     NewLoanData(address(custody), caveats, abi.encode(loanDetails)),
        //     StrategistOriginator(SO),
        //     selectedCollateral
        // );
    }

    function testNewLoanRefinanceNew() public {
        // StrategistOriginator.Details memory loanDetails = _generateOriginationDetails(
        //     ConsiderationItem({
        //         token: address(erc721s[0]),
        //         startAmount: 1,
        //         endAmount: 1,
        //         identifierOrCriteria: 1,
        //         itemType: ItemType.ERC721,
        //         recipient: payable(address(custodian))
        //     }),
        //     SpentItem({itemType: ItemType.ERC20, token: address(erc20s[0]), amount: 100, identifier: 0}),
        //     lender.addr
        // );

        // Starport.Loan memory loan = newLoan(
        //     NewLoanData(address(loanDetails.custodian), new Starport.Caveat[](0), abi.encode(loanDetails)),
        //     StrategistOriginator(SO),
        //     selectedCollateral
        // );

        // CaveatEnforcer.CaveatWithApproval memory lenderCaveat = CaveatEnforcer.CaveatWithApproval({
        //     v: 0,
        //     r: bytes32(0),
        //     s: bytes32(0),
        //     caveat: CaveatEnforcer.Caveat({
        //         enforcer: address(0),
        //         salt: bytes32(uint256(1)),
        //         deadline: block.timestamp + 1 days,
        //         data: abi.encode(uint256(0))
        //     })
        // });

        // // getLenderSignedCaveat();
        // refinanceLoan(
        //     loan,
        //     abi.encode(BasePricing.Details({rate: (uint256(1e16) * 100) / (365 * 1 days), carryRate: 0})),
        //     refinancer.addr,
        //     lenderCaveat,
        //     refinancer.addr
        // );
    }

    function testBuyNowPayLater() public {
        ConsiderationItem[] memory want = new ConsiderationItem[](1);
        want[0] = ConsiderationItem({
            token: address(erc20s[0]),
            startAmount: 100,
            endAmount: 100,
            identifierOrCriteria: 0,
            itemType: ItemType.ERC20,
            recipient: payable(seller.addr)
        });
        // //order 1, which lets is the seller, they have something that we can borrower againt (ERC721)
        // //order 2 which is the

        OfferItem[] memory sellingNFT = new OfferItem[](1);
        sellingNFT[0] = OfferItem({
            identifierOrCriteria: 1,
            token: address(erc721s[1]),
            startAmount: 1,
            endAmount: 1,
            itemType: ItemType.ERC721
        });
        OrderParameters memory thingToSell = OrderParameters({
            offerer: seller.addr,
            zone: address(0),
            offer: sellingNFT,
            consideration: want,
            orderType: OrderType.FULL_OPEN,
            startTime: block.timestamp,
            endTime: block.timestamp + 150,
            zoneHash: bytes32(0),
            salt: 0,
            conduitKey: bytes32(0),
            totalOriginalConsiderationItems: 1
        });
        bytes32 r;
        bytes32 s;
        uint8 v;
        (r, s, v) = getSignatureComponents(
            consideration, seller.key, consideration.getOrderHash(OrderParametersLib.toOrderComponents(thingToSell, 0))
        );

        Starport.Loan memory loan = generateDefaultLoanTerms();

        loan.collateral[0].token = sellingNFT[0].token;
        loan.collateral[0].identifier = sellingNFT[0].identifierOrCriteria;
        loan.collateral[0].amount = 1;

        loan.debt[0].identifier = 0;
        loan.debt[0].amount = 100;

        BNPLHelper helper = new BNPLHelper(address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));

        AdvancedOrder[] memory orders = new AdvancedOrder[](2);
        orders[0] = AdvancedOrder({
            parameters: thingToSell,
            numerator: 1,
            denominator: 1,
            signature: abi.encodePacked(r, s, v),
            extraData: ""
        });
        OrderParameters memory buyerOrderParams =
            createMirrorOrderParameters(thingToSell, payable(borrower.addr), address(0), bytes32(0));
        bytes32 buyingHash = consideration.getOrderHash(OrderParametersLib.toOrderComponents(buyerOrderParams, 0)); //0 is for the current nonce
        (r, s, v) = getSignatureComponents(consideration, borrower.key, buyingHash);
        orders[1] = AdvancedOrder({
            parameters: buyerOrderParams,
            numerator: 1,
            denominator: 1,
            signature: abi.encodePacked(r, s, v),
            extraData: ""
        });
        {
            _setApprovalsForSpentItems(loan.issuer, loan.debt);
            _setApprovalsForSpentItems(loan.borrower, loan.debt);
            _setApprovalsForSpentItems(loan.borrower, loan.collateral);
        }

        address balancerVault = address(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
        vm.etch(balancerVault, address(new FlashLoan()).code);
        deal(address(erc20s[0]), balancerVault, type(uint128).max);
        {
            Starport.Loan memory loan2 = loan;
            bytes32 buyingHash2 = buyingHash;
            Fulfillment[] memory fill = new Fulfillment[](2);
            fill[0] = Fulfillment({
                offerComponents: new FulfillmentComponent[](1),
                considerationComponents: new FulfillmentComponent[](1)
            });

            fill[0].offerComponents[0] = FulfillmentComponent({orderIndex: 0, itemIndex: 0});
            fill[0].considerationComponents[0] = FulfillmentComponent({orderIndex: 1, itemIndex: 0});
            fill[1] = Fulfillment({
                offerComponents: new FulfillmentComponent[](1),
                considerationComponents: new FulfillmentComponent[](1)
            });

            fill[1].offerComponents[0] = FulfillmentComponent({orderIndex: 1, itemIndex: 0});

            fill[1].considerationComponents[0] = FulfillmentComponent({orderIndex: 0, itemIndex: 0});

            address[] memory tokens = new address[](1);
            tokens[0] = address(erc20s[0]);
            uint256[] memory amounts = new uint256[](1);
            amounts[0] = 100;

            helper.makeFlashLoan(
                tokens,
                amounts,
                abi.encode(
                    BNPLHelper.Execution({
                        lm: address(SP),
                        seaport: address(seaport),
                        borrower: borrower.addr,
                        borrowerCaveat: signCaveatForAccount(
                            CaveatEnforcer.Caveat({
                                enforcer: address(borrowerEnforcerBNPL),
                                deadline: block.timestamp + 1 days,
                                data: abi.encode(
                                    BorrowerEnforcerBNPL.Details({
                                        loan: loan2,
                                        offerHash: buyingHash2,
                                        additionalTransfer: AdditionalTransfer({
                                            itemType: ItemType.ERC20,
                                            identifier: 0,
                                            token: address(erc20s[0]),
                                            amount: 100,
                                            from: borrower.addr,
                                            to: address(0)
                                        }),
                                        seaport: address(consideration)
                                    })
                                    )
                            }),
                            bytes32(uint256(1)),
                            borrower
                            ),
                        lenderCaveat: _generateSignedCaveatLender(loan2, lender, bytes32(uint256(1))),
                        loan: loan2,
                        orders: orders,
                        resolvers: new CriteriaResolver[](0),
                        fulfillments: fill
                    })
                )
            );
        }
    }

    function testNewLoanViaOriginatorLenderApproval() public {
        Starport.Loan memory loan = generateDefaultLoanTerms();

        StrategistOriginator.Details memory newLoanDetails = StrategistOriginator.Details({
            custodian: SP.defaultCustodian(),
            issuer: lender.addr,
            deadline: block.timestamp + 100,
            offer: StrategistOriginator.Offer({
                terms: loan.terms,
                salt: bytes32(0),
                collateral: loan.collateral,
                debt: loan.debt
            })
        });

        _setApprovalsForSpentItems(loan.borrower, loan.collateral);
        _setApprovalsForSpentItems(loan.issuer, loan.debt);

        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(strategist.key, keccak256(SO.encodeWithAccountCounter(keccak256(abi.encode(newLoanDetails)))));

        uint256 borrowerBalanceBefore = erc20s[0].balanceOf(borrower.addr);
        uint256 lenderBalanceBefore = erc20s[0].balanceOf(lender.addr);
        vm.prank(lender.addr);
        SP.setOriginateApproval(address(SO), Starport.ApprovalType.LENDER);
        vm.prank(borrower.addr);
        SO.originate(
            Originator.Request({
                borrower: borrower.addr,
                borrowerCaveat: _generateSignedCaveatBorrower(loan, borrower, bytes32(uint256(5))),
                collateral: loan.collateral,
                debt: loan.debt,
                details: abi.encode(newLoanDetails),
                approval: abi.encodePacked(r, s, v)
            })
        );
        assert(erc20s[0].balanceOf(borrower.addr) == borrowerBalanceBefore + loan.debt[0].amount);
        assert(erc20s[0].balanceOf(lender.addr) == lenderBalanceBefore - loan.debt[0].amount);
        assert(erc721s[0].ownerOf(loan.collateral[0].identifier) == address(SP.defaultCustodian()));
    }

    function testNewLoanViaOriginatorBorrowerApprovalAndLenderApproval() public {
        Starport.Loan memory loan = generateDefaultLoanTerms();

        StrategistOriginator.Details memory newLoanDetails = StrategistOriginator.Details({
            custodian: SP.defaultCustodian(),
            issuer: lender.addr,
            deadline: block.timestamp + 100,
            offer: StrategistOriginator.Offer({
                terms: loan.terms,
                salt: bytes32(0),
                collateral: loan.collateral,
                debt: loan.debt
            })
        });

        _setApprovalsForSpentItems(loan.borrower, loan.collateral);
        _setApprovalsForSpentItems(loan.issuer, loan.debt);

        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(strategist.key, keccak256(SO.encodeWithAccountCounter(keccak256(abi.encode(newLoanDetails)))));

        uint256 borrowerBalanceBefore = erc20s[0].balanceOf(borrower.addr);
        uint256 lenderBalanceBefore = erc20s[0].balanceOf(lender.addr);
        vm.prank(borrower.addr);
        SP.setOriginateApproval(address(SO), Starport.ApprovalType.BORROWER);
        vm.prank(lender.addr);
        SP.setOriginateApproval(address(SO), Starport.ApprovalType.LENDER);
        vm.prank(borrower.addr);
        SO.originate(
            Originator.Request({
                borrower: borrower.addr,
                borrowerCaveat: _emptyCaveat(),
                collateral: loan.collateral,
                debt: loan.debt,
                details: abi.encode(newLoanDetails),
                approval: abi.encodePacked(r, s, v)
            })
        );
        assert(erc20s[0].balanceOf(borrower.addr) == borrowerBalanceBefore + loan.debt[0].amount);
        assert(erc20s[0].balanceOf(lender.addr) == lenderBalanceBefore - loan.debt[0].amount);
        assert(erc721s[0].ownerOf(loan.collateral[0].identifier) == address(SP.defaultCustodian()));
    }

    event log_receivedItems(ReceivedItem[] items);

    function testSettleLoan() public {
        //     //default is 14 day term
        Starport.Loan memory activeLoan = testNewLoanERC721CollateralDefaultTerms2();

        skip(14 days);

        minimumReceived.push(
            SpentItem({itemType: ItemType.ERC20, token: address(erc20s[0]), amount: 600 ether, identifier: 0})
        );

        (ReceivedItem[] memory settlementConsideration, address restricted) =
            Settlement(activeLoan.terms.settlement).getSettlementConsideration(activeLoan);
        settlementConsideration = StarportLib.removeZeroAmountItems(settlementConsideration);
        ConsiderationItem[] memory consider = new ConsiderationItem[](
               settlementConsideration.length
             );
        uint256 i = 0;
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
        OfferItem[] memory repayOffering = new OfferItem[](
           activeLoan.collateral.length
         );
        i = 0;
        for (; i < activeLoan.collateral.length;) {
            repayOffering[i] = OfferItem({
                itemType: activeLoan.collateral[i].itemType,
                token: address(activeLoan.collateral[i].token),
                identifierOrCriteria: activeLoan.collateral[i].identifier,
                endAmount: activeLoan.collateral[i].itemType != ItemType.ERC721 ? activeLoan.collateral[i].amount : 1,
                startAmount: activeLoan.collateral[i].itemType != ItemType.ERC721 ? activeLoan.collateral[i].amount : 1
            });
            unchecked {
                ++i;
            }
        }

        OrderParameters memory op = _buildContractOrder(address(activeLoan.custodian), repayOffering, consider);
        AdvancedOrder memory settlementOrder = AdvancedOrder({
            numerator: 1,
            denominator: 1,
            parameters: op,
            extraData: abi.encode(Custodian.Command(Actions.Settlement, activeLoan, "")),
            signature: ""
        });

        consideration.fulfillAdvancedOrder({
            advancedOrder: settlementOrder,
            criteriaResolvers: new CriteriaResolver[](0),
            fulfillerConduitKey: bytes32(0),
            recipient: address(0)
        });
    }
}
