pragma solidity ^0.8.17;

import "starport-test/StarportTest.sol";
import {StarportLib, Actions} from "starport-core/lib/StarportLib.sol";
import {BNPLHelper, IFlashLoanRecipient} from "starport-test/mocks/BNPLHelper.sol";
import {Originator} from "starport-core/Originator.sol";
import {SignatureCheckerLib} from "solady/src/utils/SignatureCheckerLib.sol";

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

contract ERC1271Proxy {
    address public immutable owner;

    constructor(address owner_) {
        owner = owner_;
    }

    struct Action {
        address to;
        bytes data;
    }

    function execute(bytes[] calldata encodedAction, bytes calldata signature) public payable {
        if (msg.sender != owner) {
            require(
                SignatureCheckerLib.isValidSignatureNowCalldata(owner, keccak256(abi.encode(encodedAction)), signature),
                "invalid signature"
            );
        }
        for (uint256 i = 0; i < encodedAction.length; i++) {
            Action memory action = abi.decode(encodedAction[i], (Action));
            (bool success, bytes memory returnData) = action.to.call(action.data);
            require(success, string(returnData));
        }
    }

    function isValidSignature(bytes32 _messageHash, bytes calldata _signature)
        public
        view
        returns (bytes4 magicValue)
    {
        require(SignatureCheckerLib.isValidSignatureNowCalldata(owner, _messageHash, _signature), "invalid signature");
        return this.isValidSignature.selector;
    }
}

contract TestNewLoan is StarportTest {
    function testNewLoanERC721CollateralDefaultTerms2() public returns (Starport.Loan memory) {
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

    function testNewLoanRefinance() public {
        Starport.Loan memory loan = testNewLoanERC721CollateralDefaultTerms2();
        Starport.Loan memory refiLoan = loanCopy(loan);
        bytes memory newPricingData = abi.encode(
            SimpleInterestPricing.Details({carryRate: (uint256(1e16) * 10), rate: uint256(1e16) * 100, decimals: 18})
        );
        refiLoan.terms.pricingData = newPricingData;
        refiLoan.debt = SP.applyRefinanceConsiderationToLoan(loan.debt, new SpentItem[](0));
        LenderEnforcer.Details memory details = LenderEnforcer.Details({loan: refiLoan});

        details.loan.issuer = refinancer.addr;
        details.loan.originator = address(0);
        details.loan.start = 0;
        CaveatEnforcer.SignedCaveats memory refiCaveat = getLenderSignedCaveat({
            details: details,
            signer: refinancer,
            salt: bytes32(0),
            enforcer: address(lenderEnforcer)
        });
        _setApprovalsForSpentItems(refinancer.addr, loan.debt);

        skip(1);
        refinanceLoan(loan, newPricingData, refinancer.addr, refiCaveat, refinancer.addr);
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

        BNPLHelper helper = new BNPLHelper(address(0xBA12222222228d8Ba445958a75a0704d566BF2C8), address(this));

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
                        starport: address(SP),
                        seaport: address(seaport),
                        borrower: borrower.addr,
                        borrowerCaveat: signCaveatForAccount(
                            CaveatEnforcer.Caveat({
                                enforcer: address(borrowerEnforcerBNPL),
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
                            borrower,
                            true
                            ),
                        lenderCaveat: _generateSignedCaveatLender(loan2, lender, bytes32(uint256(1)), true),
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
            custodian: address(custodian),
            issuer: lender.addr,
            deadline: block.number + 8,
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
        assert(erc721s[0].ownerOf(loan.collateral[0].identifier) == address(address(custodian)));
    }

    function testNewLoanViaOriginatorBorrowerApprovalAndLenderApproval() public {
        Starport.Loan memory loan = generateDefaultLoanTerms();

        StrategistOriginator.Details memory newLoanDetails = StrategistOriginator.Details({
            custodian: address(custodian),
            issuer: lender.addr,
            deadline: block.number + 8,
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
        assert(erc721s[0].ownerOf(loan.collateral[0].identifier) == address(address(custodian)));
    }

    event log_receivedItems(ReceivedItem[] items);

    function testSettleLoan() public {
        //     //default is 14 day term
        Starport.Loan memory activeLoan = testNewLoanERC721CollateralDefaultTerms2();

        skip(14 days + 1);

        minimumReceived.push(
            SpentItem({itemType: ItemType.ERC20, token: address(erc20s[0]), amount: 600 ether, identifier: 0})
        );

        (ReceivedItem[] memory settlementConsideration, address authorized) =
            Settlement(activeLoan.terms.settlement).getSettlementConsideration(activeLoan);
        settlementConsideration = StarportLib.removeZeroAmountItems(settlementConsideration);
        ConsiderationItem[] memory consider = new ConsiderationItem[](settlementConsideration.length);
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
        OfferItem[] memory repayOffering = new OfferItem[](activeLoan.collateral.length);
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

    function testNewLoanAs1271ProxyAccountSender() public {
        ERC1271Proxy proxy = new ERC1271Proxy(borrower.addr);

        uint256 initial721Balance = erc721s[0].balanceOf(borrower.addr);
        assertTrue(initial721Balance > 0, "Test must have at least one erc721 token");
        uint256 initial20Balance = erc20s[0].balanceOf(borrower.addr);

        Starport.Loan memory originationDetails = _generateOriginationDetails(
            _getERC721SpentItem(erc721s[0]), _getERC20SpentItem(erc20s[0], 100), lender.addr
        );
        originationDetails.borrower = address(proxy);
        _setApprovalsForSpentItems(originationDetails.issuer, originationDetails.debt);

        CaveatEnforcer.SignedCaveats memory borrowerCaveat = _generateSignedCaveatsBorrowerProxy(
            originationDetails, address(proxy), borrower, address(borrowerEnforcer), bytes32(msg.sig), true
        );
        CaveatEnforcer.SignedCaveats memory lenderCaveat =
            _generateSignedCaveatLender(originationDetails, lender, bytes32(msg.sig), true);

        vm.prank(borrower.addr);
        erc721s[0].approve(address(proxy), 1);
        vm.prank(lender.addr);
        erc20s[0].transfer(address(proxy), 1);
        bytes[] memory actions = new bytes[](4);
        actions[0] = abi.encode(
            ERC1271Proxy.Action({
                to: address(erc721s[0]),
                data: abi.encodeWithSelector(ERC721.transferFrom.selector, borrower.addr, address(proxy), 1)
            })
        );
        actions[1] = abi.encode(
            ERC1271Proxy.Action({
                to: address(erc721s[0]),
                data: abi.encodeWithSelector(ERC721.approve.selector, address(SP), 1)
            })
        );
        actions[2] = abi.encode(
            ERC1271Proxy.Action({
                to: address(SP),
                data: abi.encodeWithSelector(
                    Starport.originate.selector,
                    new AdditionalTransfer[](0),
                    _emptyCaveat(),
                    lenderCaveat,
                    originationDetails
                    )
            })
        );
        actions[3] = abi.encode(
            ERC1271Proxy.Action({
                to: address(erc20s[0]),
                data: abi.encodeWithSelector(ERC20.transfer.selector, borrower.addr, originationDetails.debt[0].amount)
            })
        );

        bytes32 hash = keccak256(abi.encode(actions));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(borrower.key, hash);
        vm.startPrank(fulfiller.addr);
        proxy.execute(actions, abi.encodePacked(r, s, v));
    }

    function testNewLoanAs1271ProxyAccountThirdPartyFiller() public {
        ERC1271Proxy proxy = new ERC1271Proxy(borrower.addr);

        Starport.Loan memory originationDetails = _generateOriginationDetails(
            _getERC721SpentItem(erc721s[0]), _getERC20SpentItem(erc20s[0], 100), lender.addr
        );
        originationDetails.borrower = address(proxy);
        _setApprovalsForSpentItems(originationDetails.issuer, originationDetails.debt);

        CaveatEnforcer.SignedCaveats memory borrowerCaveat = _generateSignedCaveatsBorrowerProxy(
            originationDetails, address(proxy), borrower, address(borrowerEnforcer), bytes32(msg.sig), true
        );
        CaveatEnforcer.SignedCaveats memory lenderCaveat =
            _generateSignedCaveatLender(originationDetails, lender, bytes32(msg.sig), true);

        vm.prank(borrower.addr);
        erc721s[0].approve(address(proxy), 1);
        vm.prank(lender.addr);
        erc20s[0].transfer(address(proxy), 1);
        bytes[] memory actions = new bytes[](2);
        actions[0] = abi.encode(
            ERC1271Proxy.Action({
                to: address(erc721s[0]),
                data: abi.encodeWithSelector(ERC721.transferFrom.selector, borrower.addr, address(proxy), 1)
            })
        );
        actions[1] = abi.encode(
            ERC1271Proxy.Action({
                to: address(erc721s[0]),
                data: abi.encodeWithSelector(ERC721.approve.selector, address(SP), 1)
            })
        );

        bytes32 hash = keccak256(abi.encode(actions));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(borrower.key, hash);
        vm.startPrank(fulfiller.addr);
        proxy.execute(actions, abi.encodePacked(r, s, v));
        SP.originate(new AdditionalTransfer[](0), borrowerCaveat, lenderCaveat, originationDetails);
    }

    function signCaveatForProxyAccount(
        CaveatEnforcer.Caveat memory caveat,
        bytes32 salt,
        address account,
        Account memory signer,
        bool invalidate
    ) public view returns (CaveatEnforcer.SignedCaveats memory signedCaveats) {
        signedCaveats = CaveatEnforcer.SignedCaveats({
            signature: "",
            singleUse: invalidate,
            deadline: block.number + (1 days / 12),
            salt: salt,
            caveats: new CaveatEnforcer.Caveat[](1)
        });

        signedCaveats.caveats[0] = caveat;
        bytes32 hash = SP.hashCaveatWithSaltAndNonce(
            account, signedCaveats.singleUse, salt, signedCaveats.deadline, signedCaveats.caveats
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer.key, hash);
        signedCaveats.signature = abi.encodePacked(r, s, v);
    }

    function _generateSignedCaveatsBorrowerProxy(
        Starport.Loan memory loan,
        address account,
        Account memory signer,
        address enforcer,
        bytes32 salt,
        bool invalidate
    ) public view returns (CaveatEnforcer.SignedCaveats memory) {
        LenderEnforcer.Details memory details = LenderEnforcer.Details({loan: loan});
        return signCaveatForProxyAccount(
            CaveatEnforcer.Caveat({enforcer: enforcer, data: abi.encode(details)}), salt, account, signer, invalidate
        );
    }
}
