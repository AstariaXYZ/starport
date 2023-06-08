pragma solidity =0.8.17;

import {MockERC721} from "solmate/test/utils/mocks/MockERC721.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import "forge-std/Test.sol";

import "src/LoanManager.sol";

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

contract TestNFT is MockERC721 {
    constructor() MockERC721("TestNFT", "TNFT") {}
}

contract TestToken is MockERC20 {
    constructor() MockERC20("TestToken", "TTKN", 18) {}
}

contract TestStarLite is BaseOrderTest {
    //    address conduit;
    bytes32 conduitKey;

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
        UV = new UniqueValidator(LM);

        (strategist, strategistKey) = makeAddrAndKey("strategist");
        conduitKeyOne = bytes32(uint256(uint160(address(strategist))) << 96);
        vm.startPrank(strategist);
        //create conduit, update channel
        conduit = Conduit(conduitController.createConduit(conduitKeyOne, address(strategist)));
        debtToken.approve(address(conduit), 100000);
        debtToken.mint(address(strategist), 1000);
        conduitController.updateChannel(address(conduit), address(UV), true);
        conduitController.updateChannel(address(conduit), address(consideration), true);

        vm.stopPrank();
    }

    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        public
        override
        returns (bytes4)
    {
        return this.onERC721Received.selector;
    }

    function testNewLoan() public {
        TestNFT nft = new TestNFT();

        vm.label(address(debtToken), "what");
        vm.label(address(1), "borrower");

        {
            vm.startPrank(address(1));
            nft.mint(address(1), 1);
            nft.setApprovalForAll(address(consideration), true);
            vm.stopPrank();
        }

        UniqueValidator.Details memory loanDetails = UniqueValidator.Details({
            validator: address(UV),
            conduit: address(conduit),
            collateral: address(nft),
            debtToken: address(debtToken),
            identifier: 1,
            maxAmount: 100,
            rate: 1,
            duration: 1000,
            deadline: block.timestamp + 100,
            extraData: abi.encode(uint256(500 ether), uint256(100 wei), uint256(7 days)) // startPrice, endPrice, duration
        });

        bytes32 hash = keccak256(UV.encodeValidatorHash(address(1), abi.encode(loanDetails)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(strategistKey, hash);

        _executeNLR(
            nft,
            address(LM),
            LoanManager.NewLoanRequest({
                lender: address(strategist),
                details: abi.encode(loanDetails),
                borrowerDetails: LoanManager.BorrowerDetails({who: address(this), what: address(debtToken), howMuch: 100}),
                v: v,
                r: r,
                s: s
            })
        );

        // UniqueValidator.Details memory loanDetails = UniqueValidator.Details({
        //            validator: address(UV),
        //            conduit : address(conduit),
        //            token : address(nft),
        //            tokenId : 1,
        //            maxAmount : 100,
        //            rate : 1,
        //            duration : 1000,
        //            deadline : block.timestamp + 100
        //        });

        //        Validator.Loan memory l = Validator.Loan({
        //            validator : address(UV),
        //            token : address(nft),
        //            tokenId : 1,
        //            rate : 1,
        //            duration : 1000,
        //            deadline : block.timestamp + 100
        //        });
    }

    function _executeNLR(TestNFT nft, address lm, LoanManager.NewLoanRequest memory nlr) internal {
        //        nft.safeTransferFrom(address(1), lm, 1, abi.encode(nlr));
        nft.setApprovalForAll(address(consideration), true);
        //struct AdvancedOrder {
        //    OrderParameters parameters;
        //    uint120 numerator;
        //    uint120 denominator;
        //    bytes signature;
        //    bytes extraData;
        //}

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
            extraData: abi.encode(uint8(0), nlrs)
        });

        //function fulfillAdvancedOrder(
        //        AdvancedOrder calldata advancedOrder,
        //        CriteriaResolver[] calldata criteriaResolvers,
        //        bytes32 fulfillerConduitKey,
        //        address recipient
        //    ) external payable returns (bool fulfilled);
        vm.startPrank(address(1));
        consideration.fulfillAdvancedOrder({
            advancedOrder: x,
            criteriaResolvers: new CriteriaResolver[](0),
            fulfillerConduitKey: bytes32(0),
            recipient: address(this)
        });
        vm.stopPrank();
    }
}
