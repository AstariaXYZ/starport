pragma solidity =0.8.17;

import {MockERC721} from "solmate/test/utils/mocks/MockERC721.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import "forge-std/Test.sol";

import "src/LoanManager.sol";

import {
ItemType,
ReceivedItem,
SpentItem
} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {
    ConsiderationItem,
    AdvancedOrder,
    CriteriaResolver,
    OrderType
} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {BaseOrderTest} from "seaport/test/foundry/utils/BaseOrderTest.sol";
import {Conduit} from "seaport-core/src/conduit/Conduit.sol";
import {ConduitController} from "seaport-core/src/conduit/ConduitController.sol";
import {Consideration} from "seaport-core/src/lib/Consideration.sol";
import {UniqueValidator} from "src/validators/UniqueValidator.sol";
import {FixedTermPricing} from "src/pricing/Pricing.sol";
import {FixedTermTrigger} from "src/triggers/Trigger.sol";
import {DutchAuctionResolver} from "src/resolvers/DutchAuctionResolver.sol";

contract TestNFT is MockERC721 {
    constructor() MockERC721("TestNFT", "TNFT") {}
}

contract TestToken is MockERC20 {
    constructor() MockERC20("TestToken", "TTKN", 18) {}
}

contract TestStarLite is BaseOrderTest {
    //    address conduit;
    bytes32 conduitKey;

    address borrower;
    uint256 borrowerKey;
    address lender;
    uint256 lenderKey;
    address strategist;
    uint256 strategistKey;
    address seaportAddr;
    LoanManager LM;
    UniqueValidator UV;
    TestToken debtToken;

    function _deployAndConfigureConsideration() public {
        conduitController = new ConduitController();
        consideration = new Consideration(address(conduitController));
    }

    function setUp() public override {
        _deployAndConfigureConsideration();
        debtToken = new TestToken();

        LM = new LoanManager(ConsiderationInterface(address(consideration)));
        (strategist, strategistKey) = makeAddrAndKey("strategist");
        (lender, lenderKey) = makeAddrAndKey("lender");
        (borrower, borrowerKey) = makeAddrAndKey("borrower");
        UV = new UniqueValidator(LM, ConduitControllerInterface(address(conduitController)), strategist, 0);

        conduitKeyOne = bytes32(uint256(uint160(address(strategist))) << 96);
        vm.startPrank(lender);
        debtToken.approve(address(UV.conduit()), 100000);
        debtToken.mint(address(lender), 1000);

        vm.stopPrank();
    }

    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        public
        pure
        override
        returns (bytes4)
    {
        return this.onERC721Received.selector;
    }

    function testNewLoan() public {
        TestNFT nft = new TestNFT();

        vm.label(address(debtToken), "what");
        vm.label(borrower, "borrower");

        {
            vm.startPrank(borrower);
            nft.mint(borrower, 1);
            nft.setApprovalForAll(address(consideration), true);
            vm.stopPrank();
        }

//        UniqueValidator.Details memory loanDetails = UniqueValidator.Details({
//            validator: address(UV),
//            conduit: address(conduit),
//            collateral: address(nft),
//            debtToken: address(debtToken),
//            identifier: 1,
//            maxAmount: 100,
//            rate: 1,
//            loanDuration: 1000,
//            deadline: block.timestamp + 100,
//            settlement: UniqueValidator.SettlementData({startingPrice: uint(500 ether), endingPrice: 100 wei, window: 7 days})
//        });

        //struct Details {
        //    address validator;
        //    address trigger; // isLoanHealthy
        //    address resolver; // liquidationMethod
        //    address pricing; // getOwed
        //    uint256 deadline;
        //    SpentItem collateral;
        //    ReceivedItem debt;
        //    bytes pricingData;
        //    bytes resolverData;
        //  }



        UniqueValidator.Details memory loanDetails;

        {
            FixedTermPricing pricing = new FixedTermPricing();
            DutchAuctionResolver resolver = new DutchAuctionResolver();
            FixedTermTrigger trigger = new FixedTermTrigger();
            loanDetails = UniqueValidator.Details({
            validator: address(UV),
            trigger: address(trigger),
            resolver: address(resolver),
            pricing: address(pricing),
            deadline: block.timestamp + 100,
            collateral: SpentItem({token: address(nft), amount: 1, identifier: 0, itemType: ItemType.ERC721}),
            debt: ReceivedItem({recipient: payable(lender), token: address(debtToken), amount: 100, identifier: 0, itemType: ItemType.ERC20}),
            pricingData: abi.encode(FixedTermPricing.Details({rate: uint256(uint256(1e16) / 365 * 1 days), loanDuration: 10 days })),
            resolverData: abi.encode(DutchAuctionResolver.Details({startingPrice: uint256(500 ether), endingPrice: 100 wei, window: 7 days})),
            triggerData: abi.encode(FixedTermPricing.Details({rate: uint256(uint256(1e16) / 365 * 1 days), loanDuration: 10 days }))
            });
        }

        bytes32 hash = keccak256(UV.encodeWithAccountCounter(address(strategist), abi.encode(loanDetails)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(strategistKey, hash);

        _executeNLR(
            nft,
            address(LM),
            LoanManager.NewLoanRequest({
                details: abi.encode(loanDetails),
                loan: LoanManager.Loan({
                    collateral: SpentItem({token: address(nft), amount: 1, identifier: 0, itemType: ItemType.ERC721}),
                    debt: ReceivedItem({recipient: payable(borrower), token: address(debtToken), amount: 100, identifier: 0, itemType: ItemType.ERC20}),
                    validator: loanDetails.validator,
                    trigger: loanDetails.trigger,
                    resolver: loanDetails.resolver,
                    pricing: loanDetails.pricing,
                    pricingData: abi.encode(FixedTermPricing.Details({rate: uint256(uint256(1e16) / 365 * 1 days), loanDuration: 10 days })),
                    resolverData: abi.encode(DutchAuctionResolver.Details({startingPrice: uint256(500 ether), endingPrice: 100 wei, window: 7 days})),
                    triggerData: abi.encode(FixedTermPricing.Details({rate: uint256(uint256(1e16) / 365 * 1 days), loanDuration: 10 days })),
                    start: uint256(0),
                    nonce: uint256(0)
                }),
                signature: Validator.Signature({v: v, r: r, s: s})
            })
        );
    }

    function _executeNLR(TestNFT nft, address lm, LoanManager.NewLoanRequest memory nlr) internal {
        nft.setApprovalForAll(address(consideration), true);

        ConsiderationItem[] memory consider = new ConsiderationItem[](1);
        consider[0] = ConsiderationItem({
            itemType: ItemType.ERC721,
            token: address(nft),
            identifierOrCriteria: 1,
            startAmount: 1,
            endAmount: 1,
            recipient: payable(address(LM))
        });
        OrderParameters memory op = OrderParameters({
            offerer: address(LM),
            zone: address(0),
            offer: new OfferItem[](0),
            consideration: consider,
            orderType: OrderType.CONTRACT,
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            zoneHash: bytes32(0),
            salt: 0,
            conduitKey: bytes32(0),
            totalOriginalConsiderationItems: 1
        });

        LoanManager.NewLoanRequest[] memory nlrs = new LoanManager.NewLoanRequest[](1);
        nlrs[0] = nlr;

        AdvancedOrder memory x = AdvancedOrder({
            parameters: op,
            numerator: 1,
            denominator: 1,
            signature: "0x",
            extraData: abi.encode(uint8(LoanManager.Action.LOCK), nlrs)
        });

        uint256 balanceBefore = debtToken.balanceOf(borrower);
        vm.startPrank(borrower);
        consideration.fulfillAdvancedOrder({
            advancedOrder: x,
            criteriaResolvers: new CriteriaResolver[](0),
            fulfillerConduitKey: bytes32(0),
            recipient: address(this)
        });
        uint256 balanceAfter = debtToken.balanceOf(borrower);

        assertEq(balanceAfter - balanceBefore, 100);
        vm.stopPrank();
    }
}
