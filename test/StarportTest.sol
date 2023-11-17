pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Starport} from "starport-core/Starport.sol";
import {Pricing} from "starport-core/pricing/Pricing.sol";
import {StrategistOriginator} from "starport-core/originators/StrategistOriginator.sol";
import {
    ItemType,
    ReceivedItem,
    OfferItem,
    SpentItem,
    OrderParameters
} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {OrderParametersLib} from "seaport/lib/seaport-sol/src/lib/OrderParametersLib.sol";
import {AdditionalTransfer} from "starport-core/lib/StarportLib.sol";
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
import {StrategistOriginator} from "starport-core/originators/StrategistOriginator.sol";

import {SimpleInterestPricing} from "starport-core/pricing/SimpleInterestPricing.sol";

import {BasePricing} from "starport-core/pricing/BasePricing.sol";

import {FixedTermStatus} from "starport-core/status/FixedTermStatus.sol";
import {FixedTermDutchAuctionSettlement} from "starport-core/settlement/FixedTermDutchAuctionSettlement.sol";
import {DutchAuctionSettlement} from "starport-core/settlement/DutchAuctionSettlement.sol";

import {Starport} from "starport-core/Starport.sol";

import {BaseOrderTest} from "seaport/test/foundry/utils/BaseOrderTest.sol";
import {TestERC721} from "seaport/contracts/test/TestERC721.sol";
import {TestERC1155} from "seaport/contracts/test/TestERC1155.sol";
import {TestERC20} from "seaport/contracts/test/TestERC20.sol";
import {ConsiderationItemLib} from "seaport/lib/seaport-sol/src/lib/ConsiderationItemLib.sol";
//import {AAVEPoolCustodian} from "starport-core/custodians/AAVEPoolCustodian.sol";
import {Custodian} from "starport-core/Custodian.sol";
import "seaport/lib/seaport-sol/src/lib/AdvancedOrderLib.sol";
import {Status} from "starport-core/status/Status.sol";
import {Settlement} from "starport-core/settlement/Settlement.sol";
import {Pricing} from "starport-core/pricing/Pricing.sol";
import {Cast} from "starport-test/utils/Cast.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {ERC721} from "solady/src/tokens/ERC721.sol";
import {ERC1155} from "solady/src/tokens/ERC1155.sol";
import {ContractOffererInterface} from "seaport-types/src/interfaces/ContractOffererInterface.sol";
import {TokenReceiverInterface} from "starport-core/interfaces/TokenReceiverInterface.sol";
import {Actions} from "starport-core/lib/StarportLib.sol";

import {CaveatEnforcer} from "starport-core/enforcers/CaveatEnforcer.sol";
import {BorrowerEnforcer} from "starport-core/enforcers/BorrowerEnforcer.sol";
import {BorrowerEnforcerBNPL} from "starport-core/enforcers/BorrowerEnforcerBNPL.sol";

import {LenderEnforcer} from "starport-core/enforcers/LenderEnforcer.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";

interface IWETH9 {
    function deposit() external payable;

    function withdraw(uint256) external;
}

contract MockIssuer is TokenReceiverInterface {
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        override
        returns (bytes4)
    {
        return this.onERC721Received.selector;
    }

    function onERC1155Received(address operator, address from, uint256 id, uint256 value, bytes calldata data)
        external
        override
        returns (bytes4)
    {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external override returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }
}

contract StarportTest is BaseOrderTest {
    using Cast for *;
    using FixedPointMathLib for uint256;

    MockIssuer public issuer;

    Status fixedTermStatus;

    Settlement dutchAuctionSettlement;

    Pricing simpleInterestPricing;

    ConsiderationInterface public seaport;

    Pricing pricing;
    Settlement settlement;
    Status status;

    uint256 defaultLoanDuration = 14 days;

    // 1% interest rate per second
    bytes defaultPricingData =
        abi.encode(BasePricing.Details({carryRate: (uint256(1e16) * 10), rate: uint256(1e16) * 150, decimals: 18}));

    bytes defaultSettlementData = abi.encode(
        DutchAuctionSettlement.Details({startingPrice: uint256(500 ether), endingPrice: 100 wei, window: 7 days})
    );
    bytes defaultStatusData = abi.encode(FixedTermStatus.Details({loanDuration: defaultLoanDuration}));

    Account borrower;
    Account lender;
    Account seller;
    Account strategist;
    Account refinancer;
    Account fulfiller;

    address seaportAddr;
    Starport SP;
    Custodian custodian;
    StrategistOriginator SO;

    BorrowerEnforcer borrowerEnforcer;
    BorrowerEnforcerBNPL borrowerEnforcerBNPL;

    LenderEnforcer lenderEnforcer;

    function _deployAndConfigureConsideration() public {
        conduitController = new ConduitController();

        consideration = new Consideration(address(conduitController));
        seaport = consideration;
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

        // allocate funds and tokens to test addresses
        allocateTokensAndApprovals(address(this), uint128(MAX_INT));
        issuer = new MockIssuer();
        vm.label(address(issuer), "MockIssuer");
        allocateTokensAndApprovals(address(issuer), uint128(MAX_INT));
        borrower = makeAndAllocateAccount("borrower");
        lender = makeAndAllocateAccount("lender");
        strategist = makeAndAllocateAccount("strategist");
        seller = makeAndAllocateAccount("seller");
        refinancer = makeAndAllocateAccount("refinancer");
        fulfiller = makeAndAllocateAccount("fulfiller");

        SP = new Starport(address(consideration));
        custodian = Custodian(payable(SP.defaultCustodian()));
        SO = new StrategistOriginator(SP, strategist.addr, 1e16, address(this));
        pricing = new SimpleInterestPricing(SP);
        settlement = new FixedTermDutchAuctionSettlement(SP);
        status = new FixedTermStatus();
        vm.label(address(erc721s[0]), "Collateral NFT");
        vm.label(address(erc721s[1]), "Collateral2 NFT");
        vm.label(address(erc20s[0]), "Debt ERC20");
        vm.label(address(erc20s[1]), "Collateral ERC20");
        vm.label(address(erc1155s[0]), "Collateral 1155");
        vm.label(address(erc1155s[1]), "Debt 1155 ");
        vm.label(address(erc721s[2]), "Debt 721 ");
        {
            erc721s[1].mint(seller.addr, 1);
            erc721s[0].mint(borrower.addr, 1);
            erc721s[0].mint(borrower.addr, 2);
            erc721s[0].mint(borrower.addr, 3);
            erc20s[1].mint(borrower.addr, 10_000);
            erc1155s[0].mint(borrower.addr, 1, 1);
            erc1155s[1].mint(lender.addr, 1, 10);
            erc1155s[1].mint(lender.addr, 2, 10);
            erc721s[2].mint(lender.addr, 1);
        }
        borrowerEnforcer = new BorrowerEnforcer();
        borrowerEnforcerBNPL = new BorrowerEnforcerBNPL();
        lenderEnforcer = new LenderEnforcer();
        vm.label(address(borrowerEnforcer), "BorrowerEnforcer");
        vm.label(address(borrowerEnforcerBNPL), "BorrowerEnforcerBNPL");
        vm.label(address(lenderEnforcer), "LenderEnforcer");

        fixedTermStatus = new FixedTermStatus();

        dutchAuctionSettlement = new FixedTermDutchAuctionSettlement(SP);

        simpleInterestPricing = new SimpleInterestPricing(SP);
    }

    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        public
        pure
        override
        returns (bytes4)
    {
        return this.onERC721Received.selector;
    }

    // ConsiderationItem[] selectedCollateral;
    // ConsiderationItem[] collateral20;
    SpentItem[] activeDebt;

    function _setApprovalsForSpentItems(address approver, SpentItem[] memory items) internal {
        vm.startPrank(approver);
        uint256 i = 0;
        for (; i < items.length;) {
            if (items[i].itemType == ItemType.ERC20) {
                ERC20(items[i].token).approve(address(SP), type(uint256).max);
            } else if (items[i].itemType == ItemType.ERC721) {
                ERC721(items[i].token).setApprovalForAll(address(SP), true);
            } else if (items[i].itemType == ItemType.ERC1155) {
                ERC1155(items[i].token).setApprovalForAll(address(SP), true);
            }

            unchecked {
                ++i;
            }
        }
        vm.stopPrank();
    }

    function _emptyCaveat() internal returns (CaveatEnforcer.SignedCaveats memory) {
        return CaveatEnforcer.SignedCaveats({
            signature: "",
            singleUse: true,
            deadline: 0,
            salt: bytes32(0),
            caveats: new CaveatEnforcer.Caveat[](0)
        });
    }

    // loan.borrower and signer.addr could be mismatched
    function _generateSignedCaveatBorrower(Starport.Loan memory loan, Account memory signer, bytes32 salt)
        public
        view
        virtual
        returns (CaveatEnforcer.SignedCaveats memory)
    {
        loan = loanCopy(loan);
        loan.issuer = address(0);

        return _generateSignedCaveats(loan, signer, address(borrowerEnforcer), salt, true);
    }

    // loan.issuer and signer.addr could be mismatched
    function _generateSignedCaveatLender(
        Starport.Loan memory loan,
        Account memory signer,
        bytes32 salt,
        bool invalidate
    ) public view virtual returns (CaveatEnforcer.SignedCaveats memory) {
        loan = loanCopy(loan);
        loan.borrower = address(0);

        return _generateSignedCaveats(loan, signer, address(lenderEnforcer), salt, invalidate);
    }

    function loanCopy(Starport.Loan memory loan) public pure returns (Starport.Loan memory) {
        bytes memory copyBytes = abi.encode(loan);

        return abi.decode(copyBytes, (Starport.Loan));
    }

    function _generateSignedCaveats(
        Starport.Loan memory loan,
        Account memory signer,
        address enforcer,
        bytes32 salt,
        bool invalidate
    ) public view returns (CaveatEnforcer.SignedCaveats memory) {
        LenderEnforcer.Details memory details = LenderEnforcer.Details({loan: loan});
        return signCaveatForAccount(
            CaveatEnforcer.Caveat({enforcer: enforcer, data: abi.encode(details)}), salt, signer, invalidate
        );
    }

    function signCaveatForAccount(
        CaveatEnforcer.Caveat memory caveat,
        bytes32 salt,
        Account memory signer,
        bool invalidate
    ) public view returns (CaveatEnforcer.SignedCaveats memory signedCaveats) {
        signedCaveats = CaveatEnforcer.SignedCaveats({
            signature: "",
            singleUse: invalidate,
            deadline: block.timestamp + 1 days,
            salt: salt,
            caveats: new CaveatEnforcer.Caveat[](1)
        });

        signedCaveats.caveats[0] = caveat;
        bytes32 hash = SP.hashCaveatWithSaltAndNonce(
            signer.addr, signedCaveats.singleUse, salt, signedCaveats.deadline, signedCaveats.caveats
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer.key, hash);
        signedCaveats.signature = abi.encodePacked(r, s, v);
    }

    function newLoanOriginationSetup(
        Starport.Loan memory loan,
        Account memory borrowerSigner,
        bytes32 borrowerSalt,
        Account memory lenderSigner,
        bytes32 lenderSalt,
        bool invalidateLenderSalt
    )
        public
        virtual
        returns (CaveatEnforcer.SignedCaveats memory borrowerCaveat, CaveatEnforcer.SignedCaveats memory lenderCaveat)
    {
        _setApprovalsForSpentItems(loan.borrower, loan.collateral);
        _setApprovalsForSpentItems(loan.issuer, loan.debt);

        borrowerCaveat = _generateSignedCaveatBorrower(loan, borrowerSigner, borrowerSalt);
        lenderCaveat = _generateSignedCaveatLender(loan, lenderSigner, lenderSalt, invalidateLenderSalt);
    }

    function newLoanWithProvidedSigners(
        Starport.Loan memory loan,
        bytes32 borrowerSalt,
        Account memory borrowerSigner,
        bytes32 lenderSalt,
        Account memory lenderSigner,
        address fulfiller
    ) internal returns (Starport.Loan memory) {
        (CaveatEnforcer.SignedCaveats memory borrowerCaveat, CaveatEnforcer.SignedCaveats memory lenderCaveat) =
            newLoanOriginationSetup(loan, borrowerSigner, borrowerSalt, lenderSigner, lenderSalt, true);
        return newLoan(loan, borrowerCaveat, lenderCaveat, fulfiller);
    }

    function newLoan(
        Starport.Loan memory loan,
        bytes32 borrowerSalt,
        bytes32 lenderSalt,
        address fulfiller,
        bool invalidateLender
    ) internal returns (Starport.Loan memory) {
        (CaveatEnforcer.SignedCaveats memory borrowerCaveat, CaveatEnforcer.SignedCaveats memory lenderCaveat) =
            newLoanOriginationSetup(loan, borrower, borrowerSalt, lender, lenderSalt, invalidateLender);
        return newLoan(loan, borrowerCaveat, lenderCaveat, fulfiller);
    }

    function newLoan(Starport.Loan memory loan, bytes32 borrowerSalt, bytes32 lenderSalt, address fulfiller)
        internal
        returns (Starport.Loan memory)
    {
        (CaveatEnforcer.SignedCaveats memory borrowerCaveat, CaveatEnforcer.SignedCaveats memory lenderCaveat) =
            newLoanOriginationSetup(loan, borrower, borrowerSalt, lender, lenderSalt, true);
        return newLoan(loan, borrowerCaveat, lenderCaveat, fulfiller);
    }

    function newLoan(
        Starport.Loan memory loan,
        CaveatEnforcer.SignedCaveats memory borrowerCaveat,
        CaveatEnforcer.SignedCaveats memory lenderCaveat,
        address fulfiller
    ) internal returns (Starport.Loan memory originatedLoan) {
        vm.recordLogs();
        vm.startPrank(fulfiller);
        SP.originate(
            new AdditionalTransfer[](0),
            fulfiller != borrower.addr ? borrowerCaveat : _emptyCaveat(),
            fulfiller != lender.addr ? lenderCaveat : _emptyCaveat(),
            loan
        );
        vm.stopPrank();

        Vm.Log[] memory logs = vm.getRecordedLogs();

        bytes32 lienOpenTopic = bytes32(0x57cb72d73c48fadf55428537f6c9efbe080ae111339b0c5af42d9027ed20ba17);
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == lienOpenTopic) {
                (, originatedLoan) = abi.decode(logs[i].data, (uint256, Starport.Loan));
                break;
            }
        }
    }

    function getBorrowerSignedCaveat(
        BorrowerEnforcer.Details memory details,
        Account memory signer,
        bytes32 salt,
        address enforcer
    ) public view returns (CaveatEnforcer.SignedCaveats memory signedCaveats) {
        signedCaveats.caveats = new CaveatEnforcer.Caveat[](1);
        signedCaveats.salt = salt;
        signedCaveats.singleUse = true;
        signedCaveats.deadline = block.timestamp + 1 days;
        signedCaveats.caveats[0] = CaveatEnforcer.Caveat({enforcer: enforcer, data: abi.encode(details)});
        bytes32 hash = SP.hashCaveatWithSaltAndNonce(
            signer.addr, signedCaveats.singleUse, salt, signedCaveats.deadline, signedCaveats.caveats
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer.key, hash);
        signedCaveats.signature = abi.encodePacked(r, s, v);
    }

    function getLenderSignedCaveat(
        LenderEnforcer.Details memory details,
        Account memory signer,
        bytes32 salt,
        address enforcer
    ) public view returns (CaveatEnforcer.SignedCaveats memory signedCaveats) {
        signedCaveats.caveats = new CaveatEnforcer.Caveat[](1);
        signedCaveats.salt = salt;
        signedCaveats.singleUse = true;
        signedCaveats.deadline = block.timestamp + 1 days;
        signedCaveats.caveats[0] = CaveatEnforcer.Caveat({enforcer: enforcer, data: abi.encode(details)});
        bytes32 hash = SP.hashCaveatWithSaltAndNonce(
            signer.addr, signedCaveats.singleUse, salt, signedCaveats.deadline, signedCaveats.caveats
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer.key, hash);
        signedCaveats.signature = abi.encodePacked(r, s, v);
    }

    function newLoanWithDefaultTerms() public returns (Starport.Loan memory) {
        Starport.Loan memory loan = generateDefaultLoanTerms();
        return newLoan(loan, bytes32(msg.sig), bytes32(msg.sig), borrower.addr, true);
    }

    function newLoanWithDefaultTerms(bool invalidateLender) public returns (Starport.Loan memory) {
        Starport.Loan memory loan = generateDefaultLoanTerms();
        return newLoan(loan, bytes32(msg.sig), bytes32(msg.sig), borrower.addr, invalidateLender);
    }

    function generateDefaultLoanTerms() public view virtual returns (Starport.Loan memory) {
        SpentItem[] memory newCollateral = new SpentItem[](1);
        newCollateral[0] = SpentItem({itemType: ItemType.ERC721, token: address(erc721s[0]), identifier: 1, amount: 1});
        SpentItem[] memory newDebt = new SpentItem[](1);
        newDebt[0] = SpentItem({itemType: ItemType.ERC20, token: address(erc20s[0]), identifier: 0, amount: 1e18});
        return Starport.Loan({
            start: 0,
            custodian: address(custodian),
            borrower: borrower.addr,
            issuer: lender.addr,
            originator: address(0),
            collateral: newCollateral,
            debt: newDebt,
            terms: Starport.Terms({
                status: address(status),
                settlement: address(settlement),
                pricing: address(pricing),
                pricingData: defaultPricingData,
                settlementData: defaultSettlementData,
                statusData: defaultStatusData
            })
        });
    }

    // function newLoan(
    //     Starport.Loan memory loan,
    //     bytes32 borrowerSalt,
    //     bytes32 lenderSalt
    // ) internal returns (Starport.Loan memory originatedLoan) {
    //     newLoanSpecifySigner(loan, borrowerSalt, borrower, lenderSalt, lender);
    // }

    function refinanceLoan(
        Starport.Loan memory loan,
        bytes memory newPricingData,
        address asWho,
        CaveatEnforcer.SignedCaveats memory lenderCaveat,
        address lender
    ) internal returns (Starport.Loan memory newLoan) {
        return refinanceLoan(loan, newPricingData, asWho, lenderCaveat, lender, "");
    }

    function getRefinanceCaveat(Starport.Loan memory loan, bytes memory pricingData, address fulfiller)
        public
        returns (Starport.Loan memory)
    {
        (SpentItem[] memory considerationPayment, SpentItem[] memory carryPayment,) =
            Pricing(loan.terms.pricing).getRefinanceConsideration(loan, pricingData, fulfiller);
        return SP.applyRefinanceConsiderationToLoan(loan, considerationPayment, carryPayment, pricingData);
    }

    function refinanceLoan(
        Starport.Loan memory loan,
        bytes memory pricingData,
        address asWho,
        CaveatEnforcer.SignedCaveats memory lenderCaveat,
        address lender,
        bytes memory revertMessage
    ) internal returns (Starport.Loan memory newLoan) {
        vm.recordLogs();
        vm.startPrank(asWho);

        if (revertMessage.length > 0) {
            vm.expectRevert(revertMessage); //reverts InvalidContractOfferer with an address an a contract nonce so expect general revert
        }
        SP.refinance(lender, lenderCaveat, loan, pricingData);

        vm.stopPrank();

        Vm.Log[] memory logs = vm.getRecordedLogs();

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == bytes32(0x57cb72d73c48fadf55428537f6c9efbe080ae111339b0c5af42d9027ed20ba17)) {
                (, newLoan) = abi.decode(logs[i].data, (uint256, Starport.Loan));
                break;
            }
        }
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

    function _SpentItemToOfferItem(SpentItem memory item) internal pure returns (OfferItem memory) {
        return OfferItem({
            itemType: item.itemType,
            token: item.token,
            identifierOrCriteria: item.identifier,
            startAmount: item.amount,
            endAmount: item.amount
        });
    }

    function _SpentItemsToOfferItems(SpentItem[] memory items) internal pure returns (OfferItem[] memory) {
        OfferItem[] memory copiedItems = new OfferItem[](items.length);
        for (uint256 i = 0; i < items.length; i++) {
            copiedItems[i] = _SpentItemToOfferItem(items[i]);
        }
        return copiedItems;
    }

    function _toConsiderationItems(ReceivedItem[] memory _receivedItems)
        internal
        pure
        returns (ConsiderationItem[] memory)
    {
        ConsiderationItem[] memory considerationItems = new ConsiderationItem[](
            _receivedItems.length
        );
        for (uint256 i = 0; i < _receivedItems.length; ++i) {
            considerationItems[i] = ConsiderationItem(
                _receivedItems[i].itemType,
                _receivedItems[i].token,
                _receivedItems[i].identifier,
                _receivedItems[i].amount,
                _receivedItems[i].amount,
                _receivedItems[i].recipient
            );
        }
        return considerationItems;
    }

    function _settleLoan(Starport.Loan memory activeLoan, address fulfiller) internal {
        (SpentItem[] memory offer, ReceivedItem[] memory paymentConsideration) = Custodian(
            payable(activeLoan.custodian)
        ).previewOrder(
            address(consideration), fulfiller, new SpentItem[](0), new SpentItem[](0), abi.encode(activeLoan)
        );

        OrderParameters memory op = _buildContractOrder(
            address(activeLoan.custodian), _SpentItemsToOfferItems(offer), _toConsiderationItems(paymentConsideration)
        );

        AdvancedOrder memory x = AdvancedOrder({
            parameters: op,
            numerator: 1,
            denominator: 1,
            signature: "0x",
            extraData: abi.encode(Custodian.Command(Actions.Settlement, activeLoan, ""))
        });

        //        vm.recordLogs();
        vm.startPrank(borrower.addr);
        consideration.fulfillAdvancedOrder({
            advancedOrder: x,
            criteriaResolvers: new CriteriaResolver[](0),
            fulfillerConduitKey: bytes32(0),
            recipient: address(this)
        });
        //    Vm.Log[] memory logs = vm.getRecordedLogs();
    }

    function _repayLoan(Starport.Loan memory loan, address fulfiller) internal {
        uint256 repayerBefore = erc20s[0].balanceOf(fulfiller);
        uint256 lenderBefore = erc20s[0].balanceOf(lender.addr);
        uint256 originatorBefore = erc20s[0].balanceOf(loan.originator);

        BasePricing.Details memory details = abi.decode(loan.terms.pricingData, (BasePricing.Details));
        uint256 interest = SimpleInterestPricing(loan.terms.pricing).calculateInterest(
            10 days, loan.debt[0].amount, details.rate, details.decimals
        );
        uint256 carry = interest.mulWad(1e17);

        _executeRepayLoan(loan, fulfiller);

        uint256 repayerAfter = erc20s[0].balanceOf(fulfiller);
        uint256 lenderAfter = erc20s[0].balanceOf(lender.addr);
        uint256 originatorAfter = erc20s[0].balanceOf(loan.originator);

        assertEq(
            repayerBefore - (loan.debt[0].amount + interest),
            repayerAfter,
            "borrower: Borrower repayment was not correct"
        );
        assertEq(
            lenderBefore + loan.debt[0].amount + interest - carry, lenderAfter, "lender:  repayment was not correct"
        );
        assertEq(originatorBefore + carry, originatorAfter, "carry: Borrower repayment was not correct");
    }

    function getOrderHash(address contractOfferer) public returns (bytes32) {
        uint256 counter = consideration.getContractOffererNonce(contractOfferer);
        return bytes32(counter ^ (uint256(uint160(contractOfferer)) << 96));
    }

    function _executeRepayLoan(Starport.Loan memory loan, address fulfiller) internal {
        (SpentItem[] memory offer, ReceivedItem[] memory paymentConsideration) = Custodian(payable(loan.custodian))
            .previewOrder(
            address(consideration),
            loan.borrower,
            new SpentItem[](0),
            new SpentItem[](0),
            abi.encode(Custodian.Command(Actions.Repayment, loan, ""))
        );

        OrderParameters memory op = _buildContractOrder(
            address(loan.custodian), _SpentItemsToOfferItems(offer), _toConsiderationItems(paymentConsideration)
        );
        AdvancedOrder memory x = AdvancedOrder({
            parameters: op,
            numerator: 1,
            denominator: 1,
            signature: "0x",
            extraData: abi.encode(Custodian.Command(Actions.Repayment, loan, ""))
        });

        //        vm.recordLogs();
        vm.startPrank(fulfiller);
        consideration.fulfillAdvancedOrder({
            advancedOrder: x,
            criteriaResolvers: new CriteriaResolver[](0),
            fulfillerConduitKey: bytes32(0),
            recipient: fulfiller
        });
        vm.stopPrank();
        //    Vm.Log[] memory logs = vm.getRecordedLogs();
    }

    function _repayLoan(address borrower, uint256 amount, Starport.Loan memory loan) internal {
        vm.startPrank(borrower);
        erc20s[0].approve(address(consideration), amount);
        vm.stopPrank();
        _executeRepayLoan(loan, borrower);
    }

    function _createLoan721Collateral20Debt(address lender, uint256 borrowAmount, Starport.Terms memory terms)
        internal
        returns (Starport.Loan memory loan)
    {
        uint256 initial721Balance = erc721s[0].balanceOf(borrower.addr);
        assertTrue(initial721Balance > 0, "Test must have at least one erc721 token");
        uint256 initial20Balance = erc20s[0].balanceOf(borrower.addr);

        Starport.Loan memory originationDetails = _generateOriginationDetails(
            _getERC721SpentItem(erc721s[0]), _getERC20SpentItem(erc20s[0], borrowAmount), lender
        );
        originationDetails.terms = terms;
        loan = newLoan(originationDetails, bytes32(msg.sig), bytes32(msg.sig), fulfiller.addr);

        assertTrue(erc721s[0].balanceOf(borrower.addr) < initial721Balance, "Borrower ERC721 was not sent out");
        assertTrue(erc20s[0].balanceOf(borrower.addr) > initial20Balance, "Borrower did not receive ERC20");
    }

    function _createLoan20Collateral20Debt(
        address lender,
        uint256 collateralAmount,
        uint256 borrowAmount,
        Starport.Terms memory terms
    ) internal returns (Starport.Loan memory loan) {
        uint256 initial20Balance1 = erc20s[1].balanceOf(borrower.addr);
        assertTrue(initial20Balance1 > 0, "Borrower must have at least one erc20 token");

        uint256 initial20Balance0 = erc20s[0].balanceOf(borrower.addr);

        Starport.Loan memory originationDetails = _generateOriginationDetails(
            _getERC20SpentItem(erc20s[1], collateralAmount), _getERC20SpentItem(erc20s[0], borrowAmount), lender
        );
        originationDetails.terms = terms;
        loan = newLoan(originationDetails, bytes32(msg.sig), bytes32(msg.sig), fulfiller.addr);

        assertEq(
            initial20Balance1 - collateralAmount, erc20s[1].balanceOf(borrower.addr), "Borrower ERC20 was not sent out"
        );
        assertEq(initial20Balance0 + borrowAmount, erc20s[0].balanceOf(borrower.addr), "Borrower did not receive ERC20");
    }

    function _createLoan20Collateral721Debt(address lender, Starport.Terms memory terms)
        internal
        returns (Starport.Loan memory loan)
    {
        Starport.Loan memory originationDetails =
            _generateOriginationDetails(_getERC20SpentItem(erc20s[0], 20), _getERC721SpentItem(erc721s[2]), lender);
        originationDetails.terms = terms;
        return newLoan(originationDetails, bytes32(msg.sig), bytes32(msg.sig), fulfiller.addr);
    }

    function _generateOriginationDetails(SpentItem memory collateral, SpentItem memory debt, address incomingIssuer)
        internal
        view
        returns (Starport.Loan memory loan)
    {
        return _generateOriginationDetails(collateral, debt, incomingIssuer, address(custodian));
    }

    function _generateOriginationDetails(
        SpentItem memory collateral,
        SpentItem memory debt,
        address incomingIssuer,
        address incomingCustodian
    ) internal view returns (Starport.Loan memory loan) {
        loan = generateDefaultLoanTerms();
        loan.issuer = incomingIssuer;
        loan.debt[0] = debt;
        loan.collateral[0] = collateral;
        loan.custodian = incomingCustodian;
    }

    function _getERC20SpentItem(TestERC20 token, uint256 amount) internal pure returns (SpentItem memory) {
        return SpentItem({
            itemType: ItemType.ERC20,
            token: address(token),
            amount: amount,
            identifier: 0 // 0 for ERC20
        });
    }

    function _getERC721SpentItem(TestERC721 token) internal pure returns (SpentItem memory) {
        return SpentItem({itemType: ItemType.ERC721, token: address(token), amount: 1, identifier: 1});
    }

    function _getERC721SpentItem(TestERC721 token, uint256 tokenId) internal pure returns (SpentItem memory) {
        return SpentItem({itemType: ItemType.ERC721, token: address(token), amount: 1, identifier: tokenId});
    }

    function _getERC1155SpentItem(TestERC1155 token) internal pure returns (SpentItem memory) {
        return SpentItem({itemType: ItemType.ERC1155, token: address(token), amount: 1, identifier: 1});
    }
}
