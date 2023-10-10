pragma solidity =0.8.17;

import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {LoanManager} from "starport-core/LoanManager.sol";
import {Pricing} from "starport-core/pricing/Pricing.sol";
import {Originator} from "starport-core/originators/Originator.sol";
import {
    ItemType,
    ReceivedItem,
    OfferItem,
    SpentItem,
    OrderParameters
} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {OrderParametersLib} from "seaport/lib/seaport-sol/src/lib/OrderParametersLib.sol";
import {ConduitTransfer, ConduitItemType} from "seaport-types/src/conduit/lib/ConduitStructs.sol";
import {ConsiderationInterface} from "seaport-types/src/interfaces/ConsiderationInterface.sol";
import {
    ConsiderationItem,
    AdvancedOrder,
    CriteriaResolver,
    Fulfillment,
    FulfillmentComponent,
    OrderType
} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {Conduit} from "seaport-core/src/conduit/Conduit.sol";
import {ConduitController} from "seaport-core/src/conduit/ConduitController.sol";
import {Consideration} from "seaport-core/src/lib/Consideration.sol";
//import {
//  ReferenceConsideration as Consideration
//} from "seaport/reference/ReferenceConsideration.sol";
import {UniqueOriginator} from "starport-core/originators/UniqueOriginator.sol";

import {SimpleInterestPricing} from "starport-core/pricing/SimpleInterestPricing.sol";
import {CompoundInterestPricing} from "starport-core/pricing/CompoundInterestPricing.sol";
import {BasePricing} from "starport-core/pricing/BasePricing.sol";
import {AstariaV1Pricing} from "starport-core/pricing/AstariaV1Pricing.sol";
import {FixedTermHook} from "starport-core/hooks/FixedTermHook.sol";
import {AstariaV1SettlementHook} from "starport-core/hooks/AstariaV1SettlementHook.sol";
import {FixedTermDutchAuctionHandler} from "starport-core/handlers/FixedTermDutchAuctionHandler.sol";
import {DutchAuctionHandler} from "starport-core/handlers/DutchAuctionHandler.sol";
import {EnglishAuctionHandler} from "starport-core/handlers/EnglishAuctionHandler.sol";
import {AstariaV1SettlementHandler} from "starport-core/handlers/AstariaV1SettlementHandler.sol";

import {LoanManager} from "starport-core/LoanManager.sol";

import {BaseOrderTest} from "seaport/test/foundry/utils/BaseOrderTest.sol";
import {TestERC721} from "seaport/contracts/test/TestERC721.sol";
import {TestERC20} from "seaport/contracts/test/TestERC20.sol";
import {ConsiderationItemLib} from "seaport/lib/seaport-sol/src/lib/ConsiderationItemLib.sol";
import {AAVEPoolCustodian} from "starport-core/custodians/AAVEPoolCustodian.sol";
import {Custodian} from "starport-core/Custodian.sol";
import "seaport/lib/seaport-sol/src/lib/AdvancedOrderLib.sol";
import {SettlementHook} from "starport-core/hooks/SettlementHook.sol";
import {SettlementHandler} from "starport-core/handlers/SettlementHandler.sol";
import {Pricing} from "starport-core/pricing/Pricing.sol";
import {TermEnforcer} from "starport-core/enforcers/TermEnforcer.sol";
import {FixedRateEnforcer} from "starport-core/enforcers/RateEnforcer.sol";
import {CollateralEnforcer} from "starport-core/enforcers/CollateralEnforcer.sol";
import {Cast} from "starport-test/utils/Cast.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {ERC721} from "solady/src/tokens/ERC721.sol";
import {ContractOffererInterface} from "seaport-types/src/interfaces/ContractOffererInterface.sol";
import {TokenReceiverInterface} from "starport-core/interfaces/TokenReceiverInterface.sol";

interface IWETH9 {
    function deposit() external payable;

    function withdraw(uint256) external;
}

contract StarPortTest is BaseOrderTest {
    using Cast for *;

    SettlementHook fixedTermHook;
    SettlementHook astariaSettlementHook;

    SettlementHandler dutchAuctionHandler;
    SettlementHandler englishAuctionHandler;
    SettlementHandler astariaSettlementHandler;

    Pricing simpleInterestPricing;
    Pricing astariaPricing;

    ConsiderationInterface public constant seaport = ConsiderationInterface(0x2e234DAe75C793f67A35089C9d99245E1C58470b);

    Pricing pricing;
    SettlementHandler handler;
    SettlementHook hook;

    uint256 defaultLoanDuration = 14 days;

    // 1% interest rate per second
    bytes defaultPricingData =
        abi.encode(BasePricing.Details({carryRate: (uint256(1e16) * 10), rate: (uint256(1e16) * 150) / (365 * 1 days)}));

    bytes defaultHandlerData = abi.encode(
        DutchAuctionHandler.Details({startingPrice: uint256(500 ether), endingPrice: 100 wei, window: 7 days})
    );
    bytes defaultHookData = abi.encode(FixedTermHook.Details({loanDuration: defaultLoanDuration}));

    Account borrower;
    Account lender;
    Account seller;
    Account strategist;
    Account refinancer;

    bytes32 conduitKey;
    address lenderConduit;
    address refinancerConduit;
    address seaportAddr;
    LoanManager LM;
    Custodian custodian;
    UniqueOriginator UO;

    bytes32 conduitKeyRefinancer;

    function _deployAndConfigureConsideration() public {
        conduitController = new ConduitController();

        consideration = new Consideration(address(conduitController));
        seaportAddr = address(seaport);
    }

    function setUp() public virtual override {
        _deployAndConfigureConsideration();
        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(cal, "cal");
        vm.label(address(this), "testContract");

        _deployTestTokenContracts();

        erc20s = [token1, token2, token3];
        erc721s = [test721_1, test721_2, test721_3];
        erc1155s = [test1155_1, test1155_2, test1155_3];
        vm.label(address(erc20s[0]), "debtToken");
        vm.label(address(erc721s[0]), "721 collateral 1");
        vm.label(address(erc721s[1]), "721 collateral 2");
        vm.label(address(erc1155s[0]), "1155 collateral 1");
        vm.label(address(erc1155s[1]), "1155 collateral 2");

        // allocate funds and tokens to test addresses
        allocateTokensAndApprovals(address(this), uint128(MAX_INT));

        borrower = makeAndAllocateAccount("borrower");
        lender = makeAndAllocateAccount("lender");
        strategist = makeAndAllocateAccount("strategist");
        seller = makeAndAllocateAccount("seller");
        refinancer = makeAndAllocateAccount("refinancer");

        LM = new LoanManager(consideration);
        custodian = new Custodian(LM, seaportAddr);
        UO = new UniqueOriginator(LM, strategist.addr, 1e16);
        pricing = new SimpleInterestPricing(LM);
        handler = new FixedTermDutchAuctionHandler(LM);
        hook = new FixedTermHook();
        vm.label(address(erc721s[0]), "Collateral NFT");
        vm.label(address(erc721s[1]), "Collateral2 NFT");
        vm.label(address(erc20s[0]), "Debt Token");
        vm.label(address(erc20s[1]), "Collateral Token");
        {
            vm.startPrank(borrower.addr);
            erc721s[1].mint(seller.addr, 1);
            erc721s[0].mint(borrower.addr, 1);
            erc721s[0].mint(borrower.addr, 2);
            erc721s[0].mint(borrower.addr, 3);
            erc20s[1].mint(borrower.addr, 10000);
            vm.stopPrank();
        }
        conduitKeyOne = bytes32(uint256(uint160(address(lender.addr))) << 96);
        conduitKeyRefinancer = bytes32(uint256(uint160(address(refinancer.addr))) << 96);

        vm.startPrank(lender.addr);
        lenderConduit = conduitController.createConduit(conduitKeyOne, lender.addr);

        conduitController.updateChannel(lenderConduit, address(UO), true);
        erc20s[0].approve(address(lenderConduit), 100000);
        vm.stopPrank();
        vm.startPrank(refinancer.addr);
        refinancerConduit = conduitController.createConduit(conduitKeyRefinancer, refinancer.addr);
        // console.log("Refinancer", refinancer.addr);
        conduitController.updateChannel(refinancerConduit, address(LM), true);
        erc20s[0].approve(address(refinancerConduit), 100000);
        vm.stopPrank();

        /////////

        fixedTermHook = new FixedTermHook();
        astariaSettlementHook = new AstariaV1SettlementHook(LM);

        dutchAuctionHandler = new FixedTermDutchAuctionHandler(LM);
        englishAuctionHandler = new EnglishAuctionHandler({
            LM_: LM,
            consideration_: seaport,
            EAZone_: 0x110b2B128A9eD1be5Ef3232D8e4E41640dF5c2Cd
        });
        astariaSettlementHandler = new AstariaV1SettlementHandler(LM);

        simpleInterestPricing = new SimpleInterestPricing(LM);
        astariaPricing = new AstariaV1Pricing(LM);
    }

    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        public
        pure
        override
        returns (bytes4)
    {
        return this.onERC721Received.selector;
    }

    ConsiderationItem[] selectedCollateral;
    ConsiderationItem[] collateral20;
    SpentItem[] debt;

    struct NewLoanData {
        address custodian;
        LoanManager.Caveat[] caveats;
        bytes details;
    }

    function newLoan(NewLoanData memory loanData, Originator originator, ConsiderationItem[] storage collateral)
        internal
        returns (LoanManager.Loan memory)
    {
        bool isTrusted = loanData.caveats.length == 0;
        {
            bytes32 detailsHash = keccak256(originator.encodeWithAccountCounter(keccak256(loanData.details)));
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(strategist.key, detailsHash);
            LoanManager.Loan memory loan = LoanManager.Loan({
                custodian: address(loanData.custodian),
                issuer: address(0),
                borrower: borrower.addr,
                originator: isTrusted ? address(originator) : address(0),
                terms: originator.terms(loanData.details),
                debt: debt,
                collateral: ConsiderationItemLib.toSpentItemArray(collateral),
                start: uint256(0)
            });
            return _executeNLR(
                LoanManager.Obligation({
                    custodian: address(loanData.custodian),
                    borrower: borrower.addr,
                    debt: debt,
                    salt: bytes32(0),
                    details: loanData.details,
                    approval: abi.encodePacked(r, s, v),
                    caveats: loanData.caveats,
                    originator: address(originator)
                }),
                collateral // for building contract offer
            );
        }
    }

    function buyNowPayLater(
        AdvancedOrder memory thingToBuy,
        NewLoanData memory loanData,
        Originator originator,
        ConsiderationItem[] storage collateral
    ) internal {
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(strategist.key, keccak256(originator.encodeWithAccountCounter(keccak256(loanData.details))));

        LoanManager.Loan memory loan = LoanManager.Loan({
            custodian: address(loanData.custodian),
            issuer: address(0),
            borrower: borrower.addr,
            originator: address(0),
            terms: originator.terms(loanData.details),
            debt: debt,
            collateral: ConsiderationItemLib.toSpentItemArray(collateral),
            start: uint256(0)
        });

        _buyNowPLNLR(
            thingToBuy,
            LoanManager.Obligation({
                custodian: address(loanData.custodian),
                borrower: borrower.addr,
                debt: debt,
                details: loanData.details,
                salt: bytes32(0),
                approval: abi.encodePacked(r, s, v),
                caveats: loanData.caveats,
                originator: address(originator)
            }),
            collateral // for building contract offer
        );
    }

    function _buildContractOrder(address offerer, OfferItem[] memory offer, ConsiderationItem[] memory consider)
        internal
        view
        returns (OrderParameters memory op)
    {
        op = OrderParameters({
            offerer: offerer,
            zone: address(0),
            offer: offer,
            consideration: consider,
            orderType: OrderType.CONTRACT,
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            zoneHash: bytes32(0),
            salt: 0,
            conduitKey: bytes32(0),
            totalOriginalConsiderationItems: consider.length
        });
    }

    function _executeRepayLoan(LoanManager.Loan memory activeLoan) internal {
        (ReceivedItem[] memory loanPayment, ReceivedItem[] memory carryPayment) =
            Pricing(activeLoan.terms.pricing).getPaymentConsideration(activeLoan);
        uint256 i = 0;
        ConsiderationItem[] memory consider = new ConsiderationItem[](
            loanPayment.length + carryPayment.length
        );
        for (; i < loanPayment.length;) {
            consider[i].token = loanPayment[i].token;
            consider[i].itemType = loanPayment[i].itemType;
            consider[i].identifierOrCriteria = loanPayment[i].identifier;
            consider[i].startAmount = 5 ether;
            //TODO: update this
            consider[i].endAmount = 5 ether;
            consider[i].recipient = loanPayment[i].recipient;
            unchecked {
                ++i;
            }
        }
        for (; i < carryPayment.length;) {
            consider[i].token = carryPayment[i].token;
            consider[i].itemType = carryPayment[i].itemType;
            consider[i].identifierOrCriteria = carryPayment[i].identifier;
            consider[i].startAmount = carryPayment[i].amount;
            //TODO: update this
            consider[i].endAmount = carryPayment[i].amount;
            consider[i].recipient = carryPayment[i].recipient;
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
        OrderParameters memory op = _buildContractOrder(address(custodian), repayOffering, consider);

        AdvancedOrder memory x = AdvancedOrder({
            parameters: op,
            numerator: 1,
            denominator: 1,
            signature: "0x",
            extraData: abi.encode(activeLoan)
        });

        uint256 balanceBefore = erc20s[0].balanceOf(borrower.addr);
        //        vm.recordLogs();
        vm.startPrank(borrower.addr);
        consideration.fulfillAdvancedOrder({
            advancedOrder: x,
            criteriaResolvers: new CriteriaResolver[](0),
            fulfillerConduitKey: bytes32(0),
            recipient: address(this)
        });
        //    Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 balanceAfter = erc20s[0].balanceOf(borrower.addr);

        vm.stopPrank();
    }

    function _buyNowPLNLR(
        AdvancedOrder memory x,
        //    LoanManager.Loan memory loanAsk,
        LoanManager.Obligation memory nlr,
        ConsiderationItem[] memory collateral // collateral (nft) and weth (purchase price is incoming weth plus debt)
    ) internal returns (LoanManager.Loan memory loan) {
        //use murky to create a tree that is good

        bytes32 caveatHash =
            keccak256(LM.encodeWithSaltAndBorrowerCounter(nlr.borrower, nlr.salt, keccak256(abi.encode(nlr.caveats))));
        OfferItem[] memory offer = new OfferItem[](nlr.debt.length + 1);

        for (uint256 i; i < debt.length;) {
            offer[i] = OfferItem({
                itemType: debt[i].itemType,
                token: debt[i].token,
                identifierOrCriteria: debt[i].identifier,
                startAmount: debt[i].amount,
                endAmount: debt[i].amount
            });
            unchecked {
                ++i;
            }
        }

        offer[nlr.debt.length] = OfferItem({
            itemType: ItemType.ERC721,
            token: address(LM),
            identifierOrCriteria: uint256(caveatHash),
            startAmount: 1,
            endAmount: 1
        });

        OfferItem[] memory zOffer = new OfferItem[](1);
        zOffer[0] = OfferItem({
            itemType: nlr.debt[0].itemType,
            token: nlr.debt[0].token,
            identifierOrCriteria: nlr.debt[0].identifier,
            startAmount: x.parameters.consideration[0].startAmount - nlr.debt[0].amount,
            endAmount: x.parameters.consideration[0].startAmount - nlr.debt[0].amount
        });
        ConsiderationItem[] memory zConsider = new ConsiderationItem[](1);
        zConsider[0] = ConsiderationItem({
            itemType: ItemType.ERC721,
            token: address(LM),
            identifierOrCriteria: uint256(caveatHash),
            startAmount: 1,
            endAmount: 1,
            recipient: payable(address(nlr.borrower))
        });
        OrderParameters memory zOP = OrderParameters({
            offerer: address(nlr.borrower),
            zone: address(0),
            offer: zOffer,
            consideration: zConsider,
            orderType: OrderType.FULL_OPEN,
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            zoneHash: bytes32(0),
            salt: 0,
            conduitKey: bytes32(0),
            totalOriginalConsiderationItems: 1
        });
        AdvancedOrder memory z =
            AdvancedOrder({parameters: zOP, numerator: 1, denominator: 1, signature: "", extraData: ""});

        AdvancedOrder[] memory orders = new AdvancedOrder[](3);
        orders[0] = x;
        orders[1] = AdvancedOrder({
            parameters: _buildContractOrder(address(LM), offer, collateral),
            numerator: 1,
            denominator: 1,
            signature: "",
            extraData: abi.encode(nlr)
        });
        orders[2] = z;

        // x is offering erc721 1 to satisfy y consideration
        Fulfillment[] memory fill = new Fulfillment[](4);
        fill[0] = Fulfillment({
            offerComponents: new FulfillmentComponent[](1),
            considerationComponents: new FulfillmentComponent[](1)
        });

        fill[0].offerComponents[0] = FulfillmentComponent({orderIndex: 1, itemIndex: 0});
        fill[0].considerationComponents[0] = FulfillmentComponent({orderIndex: 0, itemIndex: 0});
        fill[1] = Fulfillment({
            offerComponents: new FulfillmentComponent[](1),
            considerationComponents: new FulfillmentComponent[](1)
        });

        fill[1].offerComponents[0] = FulfillmentComponent({orderIndex: 2, itemIndex: 0});

        fill[1].considerationComponents[0] = FulfillmentComponent({orderIndex: 0, itemIndex: 0});

        fill[2] = Fulfillment({
            offerComponents: new FulfillmentComponent[](1),
            considerationComponents: new FulfillmentComponent[](1)
        });

        fill[2].offerComponents[0] = FulfillmentComponent({orderIndex: 0, itemIndex: 0});

        fill[2].considerationComponents[0] = FulfillmentComponent({orderIndex: 1, itemIndex: 0});

        fill[3] = Fulfillment({
            offerComponents: new FulfillmentComponent[](1),
            considerationComponents: new FulfillmentComponent[](1)
        });

        fill[3].offerComponents[0] = FulfillmentComponent({orderIndex: 1, itemIndex: 1});

        fill[3].considerationComponents[0] = FulfillmentComponent({orderIndex: 2, itemIndex: 0});

        uint256 balanceBefore = erc20s[0].balanceOf(seller.addr);
        vm.recordLogs();
        vm.startPrank(borrower.addr);

        consideration.matchAdvancedOrders(orders, new CriteriaResolver[](0), fill, address(borrower.addr));

        Vm.Log[] memory logs = vm.getRecordedLogs();

        //    console.logBytes32(logs[logs.length - 4].topics[0]);
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == bytes32(0x57cb72d73c48fadf55428537f6c9efbe080ae111339b0c5af42d9027ed20ba17)) {
                (, loan) = abi.decode(logs[i].data, (uint256, LoanManager.Loan));
                break;
            }
        }

        assertEq(erc721s[1].ownerOf(1), address(nlr.custodian));
        assertEq(erc20s[0].balanceOf(seller.addr), balanceBefore + x.parameters.consideration[0].startAmount);
        vm.stopPrank();
    }

    function _executeNLR(LoanManager.Obligation memory nlr, ConsiderationItem[] memory collateral)
        internal
        returns (LoanManager.Loan memory loan)
    {
        bytes32 caveatHash =
            keccak256(LM.encodeWithSaltAndBorrowerCounter(nlr.borrower, nlr.salt, keccak256(abi.encode(nlr.caveats))));
        OfferItem[] memory offer = new OfferItem[](nlr.debt.length + 1);

        for (uint256 i; i < debt.length;) {
            offer[i] = OfferItem({
                itemType: debt[i].itemType,
                token: debt[i].token,
                identifierOrCriteria: debt[i].identifier,
                startAmount: debt[i].amount,
                endAmount: debt[i].amount
            });
            unchecked {
                ++i;
            }
        }

        offer[nlr.debt.length] = OfferItem({
            itemType: ItemType.ERC721,
            token: address(LM),
            identifierOrCriteria: uint256(caveatHash),
            startAmount: 1,
            endAmount: 1
        });

        OrderParameters memory op =
            _buildContractOrder(address(LM), nlr.caveats.length == 0 ? new OfferItem[](0) : offer, collateral);

        AdvancedOrder memory x =
            AdvancedOrder({parameters: op, numerator: 1, denominator: 1, signature: "0x", extraData: abi.encode(nlr)});

        uint256 balanceBefore;
        if (debt[0].token == address(0)) {
            balanceBefore = borrower.addr.balance;
        } else {
            balanceBefore = ERC20(debt[0].token).balanceOf(borrower.addr);
        }
        vm.recordLogs();
        vm.startPrank(borrower.addr);
        consideration.fulfillAdvancedOrder({
            advancedOrder: x,
            criteriaResolvers: new CriteriaResolver[](0),
            fulfillerConduitKey: bytes32(0),
            recipient: address(borrower.addr)
        });
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 loanId;

        //    console.logBytes32(logs[logs.length - 4].topics[0]);
        bytes32 lienOpenTopic = bytes32(0x57cb72d73c48fadf55428537f6c9efbe080ae111339b0c5af42d9027ed20ba17);
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == lienOpenTopic) {
                (loanId, loan) = abi.decode(logs[i].data, (uint256, LoanManager.Loan));
                break;
            }
        }

        uint256 balanceAfter;
        if (debt[0].token == address(0)) {
            balanceAfter = borrower.addr.balance;
        } else {
            balanceAfter = ERC20(debt[0].token).balanceOf(borrower.addr);
        }

        assertEq(balanceAfter - balanceBefore, debt[0].amount);
        vm.stopPrank();
    }

    function _repayLoan(address borrower, uint256 amount, LoanManager.Loan memory loan) internal {
        vm.startPrank(borrower);
        erc20s[0].approve(address(consideration), amount);
        vm.stopPrank();
        _executeRepayLoan(loan);
    }

    function _createLoan721Collateral20Debt(address lender, uint256 borrowAmount, LoanManager.Terms memory terms)
        internal
        returns (LoanManager.Loan memory loan)
    {
        uint256 initial721Balance = erc721s[0].balanceOf(borrower.addr);
        assertTrue(initial721Balance > 0, "Test must have at least one erc721 token");
        uint256 initial20Balance = erc20s[0].balanceOf(borrower.addr);

        loan = _createLoan({
            lender: lender,
            terms: terms,
            collateralItem: ConsiderationItem({
                token: address(erc721s[0]),
                startAmount: 1,
                endAmount: 1,
                identifierOrCriteria: 1,
                itemType: ItemType.ERC721,
                recipient: payable(address(custodian))
            }),
            debtItem: SpentItem({itemType: ItemType.ERC20, token: address(erc20s[0]), amount: borrowAmount, identifier: 0})
        });

        assertTrue(erc721s[0].balanceOf(borrower.addr) < initial721Balance, "Borrower ERC721 was not sent out");
        assertTrue(erc20s[0].balanceOf(borrower.addr) > initial20Balance, "Borrower did not receive ERC20");
    }

    // TODO update or overload to take interest rate
    function _createLoan20Collateral20Debt(
        address lender,
        uint256 collateralAmount,
        uint256 borrowAmount,
        LoanManager.Terms memory terms
    ) internal returns (LoanManager.Loan memory loan) {
        uint256 initial20Balance1 = erc20s[1].balanceOf(borrower.addr);
        assertTrue(initial20Balance1 > 0, "Borrower must have at least one erc20 token");

        uint256 initial20Balance0 = erc20s[0].balanceOf(borrower.addr);

        loan = _createLoan({
            lender: lender,
            terms: terms,
            collateralItem: ConsiderationItem({
                token: address(erc20s[1]),
                startAmount: collateralAmount,
                endAmount: collateralAmount,
                identifierOrCriteria: 0,
                itemType: ItemType.ERC20,
                recipient: payable(address(custodian))
            }),
            debtItem: SpentItem({itemType: ItemType.ERC20, token: address(erc20s[0]), amount: borrowAmount, identifier: 0})
        });

        assertEq(
            initial20Balance1 - collateralAmount, erc20s[1].balanceOf(borrower.addr), "Borrower ERC20 was not sent out"
        );
        assertEq(initial20Balance0 + borrowAmount, erc20s[0].balanceOf(borrower.addr), "Borrower did not receive ERC20");
    }

    // TODO fix
    function _createLoan20Collateral721Debt(address lender, LoanManager.Terms memory terms)
        internal
        returns (LoanManager.Loan memory loan)
    {
        return _createLoan({
            lender: lender,
            terms: terms,
            collateralItem: ConsiderationItem({
                token: address(erc20s[0]),
                startAmount: 20,
                endAmount: 20,
                identifierOrCriteria: 0,
                itemType: ItemType.ERC20,
                recipient: payable(address(custodian))
            }),
            debtItem: SpentItem({itemType: ItemType.ERC721, token: address(erc721s[0]), amount: 1, identifier: 0})
        });
    }

    function _createLoan(
        address lender,
        LoanManager.Terms memory terms,
        ConsiderationItem memory collateralItem,
        SpentItem memory debtItem
    ) internal returns (LoanManager.Loan memory loan) {
        selectedCollateral.push(collateralItem);
        debt.push(debtItem);

        Originator.Details memory loanDetails = Originator.Details({
            conduit: address(lenderConduit),
            custodian: address(custodian),
            issuer: lender,
            deadline: block.timestamp + 100,
            offer: Originator.Offer({
                salt: bytes32(0),
                terms: terms,
                collateral: ConsiderationItemLib.toSpentItemArray(selectedCollateral),
                debt: debt
            })
        });

        loan = newLoan(
            NewLoanData({
                custodian: address(custodian),
                caveats: new LoanManager.Caveat[](0), // TODO check
                details: abi.encode(loanDetails)
            }),
            Originator(UO),
            selectedCollateral
        );
    }

    function _createLoanWithCaveat(
        address lender,
        LoanManager.Terms memory terms,
        ConsiderationItem memory collateralItem,
        SpentItem memory debtItem,
        LoanManager.Caveat[] memory caveats
    ) internal returns (LoanManager.Loan memory loan) {
        selectedCollateral.push(collateralItem);
        debt.push(debtItem);

        Originator.Details memory loanDetails = Originator.Details({
            conduit: address(lenderConduit),
            custodian: address(custodian),
            issuer: lender,
            deadline: block.timestamp + 100,
            offer: Originator.Offer({
                salt: bytes32(0),
                terms: terms,
                collateral: ConsiderationItemLib.toSpentItemArray(selectedCollateral),
                debt: debt
            })
        });

        loan = newLoan(
            NewLoanData({
                custodian: address(custodian),
                caveats: caveats, // TODO check
                details: abi.encode(loanDetails)
            }),
            Originator(UO),
            selectedCollateral
        );
    }

    function _getERC20SpentItem(TestERC20 token, uint256 amount) internal view returns (SpentItem memory) {
        return SpentItem({
            itemType: ItemType.ERC20,
            token: address(token),
            amount: amount,
            identifier: 0 // 0 for ERC20
        });
    }

    function _getERC721Consideration(TestERC721 token) internal view returns (ConsiderationItem memory) {
        return ConsiderationItem({
            token: address(token),
            startAmount: 1,
            endAmount: 1,
            identifierOrCriteria: 1,
            itemType: ItemType.ERC721,
            recipient: payable(address(custodian))
        });
    }
}
