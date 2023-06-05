pragma solidity =0.8.17;


import {MockERC721} from "solmate/test/utils/mocks/MockERC721.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import "forge-std/Test.sol";

import "src/LoanManager.sol";

import {ConsiderationItem, AdvancedOrder, CriteriaResolver, OrderType} from "seaport-types/src/lib/ConsiderationStructs.sol";
import { BaseOrderTest } from "seaport/test/foundry/utils/BaseOrderTest.sol";
import { Conduit } from "seaport-core/src/conduit/Conduit.sol";
import { ConduitController } from "seaport-core/src/conduit/ConduitController.sol";
import { Consideration } from "seaport-core/src/lib/Consideration.sol";
contract TestNFT is MockERC721 {
    constructor() MockERC721("TestNFT", "TNFT") {}
}

contract TestToken is MockERC20 {
    constructor() MockERC20("TestToken", "TTKN", 18) {}
}

contract TestStarLite is BaseOrderTest, IVault {

//    address conduit;
    bytes32 conduitKey;

    address strategist;
    address seaportAddr;
    LoanManager LM;


    function _deployAndConfigureConsideration() public {
        conduitController = new ConduitController();
        consideration = new Consideration(address(conduitController));

        //create conduit, update channel
        conduit = Conduit(
            conduitController.createConduit(conduitKeyOne, address(this))
        );
        conduitController.updateChannel(
            address(conduit),
            address(consideration),
            true
        );
        conduitController.updateChannel(
            address(conduit),
            address(this),
            true
        );
    }

    function setUp() override public {
        conduitKeyOne = bytes32(uint256(uint160(address(this))) << 96);

        _deployAndConfigureConsideration();

        LM = new LoanManager(address(consideration));

    }

    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) public override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function verifyAndExecute(bytes32 loanHash, uint8 v, bytes32 r, bytes32 s, ConduitTransfer memory ct) external returns (bool) {


        //TODO: eip 712
        if (strategist == ecrecover(loanHash, v, r, s)) {
            ConduitTransfer[] memory cts = new ConduitTransfer[](1);
            cts[0] = ct;
            Conduit(conduit).execute(cts);
            return true;
        }
        return false;
    }

    function testNewLoan() public {

        TestNFT nft = new TestNFT();
        TestToken debtToken = new TestToken();

        vm.label(address(debtToken), "what");
        vm.label(address(1), "borrower");


        {
            debtToken.approve(address(conduit), 100000);
            debtToken.mint(address(this), 1000);
            vm.startPrank(address(1));
            nft.mint(address(1), 1);
            //setup lender and borrower approvals


            nft.setApprovalForAll(address(consideration), true);
            vm.stopPrank();
        }


        UniqueValidator uv = new UniqueValidator();

        UniqueValidator.Details memory loanDetails = UniqueValidator.Details({
            vault : address(this),
            token : address(nft),
            tokenId : 1,
            maxAmount : 100,
            rate : 1,
            duration : 1000,
            initialAsk : 5000
        });

        uint256 strategistKey;
        (strategist, strategistKey) = makeAddrAndKey("strategist");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(strategistKey, keccak256(abi.encode(loanDetails)));


        _executeNLR(nft, address(LM), LoanManager.NewLoanRequest({
            deadline : block.timestamp + 100,
            validator : address(uv),
            borrowerDetails : LoanManager.BorrowerDetails({
                who : address(this),
                what : address(debtToken),
                howMuch : 100
            }),
            details : abi.encode(loanDetails),
            v : v,
            r : r,
            s : s
        }));

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
            itemType : ItemType.ERC721,
            token : address(nft),
            identifierOrCriteria : 1,
            startAmount : 1,
            endAmount : 1,
            recipient: payable(address(LM))
        });
        OrderParameters memory op = OrderParameters({
        offerer : address(LM),
        zone : address(0),
        offer : new OfferItem[](0),
        consideration : consider,
            orderType : OrderType.CONTRACT,
            startTime : block.timestamp,
            endTime : block.timestamp + 100,
            zoneHash : bytes32(0),
            salt : 0,
            conduitKey : bytes32(0),
            totalOriginalConsiderationItems : 1
        });

        AdvancedOrder memory x = AdvancedOrder({
            parameters : op,
            numerator : 1,
            denominator : 1,
            signature : "0x",
            extraData : abi.encode(uint8(0), nlr)
        });

        //function fulfillAdvancedOrder(
        //        AdvancedOrder calldata advancedOrder,
        //        CriteriaResolver[] calldata criteriaResolvers,
        //        bytes32 fulfillerConduitKey,
        //        address recipient
        //    ) external payable returns (bool fulfilled);
        vm.startPrank(address(1));
        consideration.fulfillAdvancedOrder({
        advancedOrder : x,
        criteriaResolvers : new CriteriaResolver[](0),
        fulfillerConduitKey : bytes32(0),
        recipient : address(this)
        });
        vm.stopPrank();
    }
}