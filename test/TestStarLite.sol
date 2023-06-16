pragma solidity =0.8.17;

import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {LoanManager} from "src/LoanManager.sol";
import {Pricing} from "src/pricing/Pricing.sol";
import {Originator} from "src/originators/Originator.sol";
import {
    ItemType,
    ReceivedItem,
    OfferItem,
    SpentItem,
    OrderParameters
} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {ConduitTransfer, ConduitItemType} from "seaport-types/src/conduit/lib/ConduitStructs.sol";
import {ConsiderationInterface} from "seaport-types/src/interfaces/ConsiderationInterface.sol";
import {
    ConsiderationItem,
    AdvancedOrder,
    CriteriaResolver,
    OrderType
} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {Conduit} from "seaport-core/src/conduit/Conduit.sol";
import {ConduitController} from "seaport-core/src/conduit/ConduitController.sol";
import {Consideration} from "seaport-core/src/lib/Consideration.sol";
import {UniqueOriginator} from "src/originators/UniqueOriginator.sol";
import {FixedTermPricing} from "src/pricing/FixedTermPricing.sol";
import {FixedTermHook} from "src/hooks/FixedTermHook.sol";
import {DutchAuctionHandler} from "src/handlers/DutchAuctionHandler.sol";
import {Merkle} from "seaport/lib/murky/src/Merkle.sol";
//contract TestNFT is MockERC721 {
//  constructor() MockERC721("TestNFT", "TNFT") {}
//}
//
//contract TestToken is MockERC20 {
//  constructor() MockERC20("TestToken", "TTKN", 18) {}
//}
import {BaseOrderTest} from "seaport/test/foundry/utils/BaseOrderTest.sol";
import {TestERC721} from "seaport/contracts/test/TestERC721.sol";
import {TestERC20} from "seaport/contracts/test/TestERC20.sol";
import {ConsiderationItemLib} from "seaport/lib/seaport-sol/src/lib/ConsiderationItemLib.sol";

contract TestStarLite is BaseOrderTest {
    Account borrower;
    Account lender;
    Account strategist;

    bytes32 conduitKey;
    address lenderConduit;
    address seaportAddr;
    LoanManager LM;
    UniqueOriginator UO;

    function _deployAndConfigureConsideration() public {
        conduitController = new ConduitController();
        consideration = new Consideration(address(conduitController));
    }

    function setUp() public override {
        _deployAndConfigureConsideration();
        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(cal, "cal");
        vm.label(address(this), "testContract");

        _deployTestTokenContracts();
        console.log(address(consideration));
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

        LM = new LoanManager();
        UO = new UniqueOriginator(LM, strategist.addr, 1e16);

        vm.label(address(erc721s[0]), "Collateral NFT");
        vm.label(address(erc721s[1]), "Debt NFT");
        vm.label(address(erc20s[0]), "Debt Token");
        vm.label(address(erc20s[1]), "Collateral Token");
        {
            vm.startPrank(borrower.addr);
            erc721s[0].mint(borrower.addr, 1);
            erc721s[0].mint(borrower.addr, 2);
            erc721s[0].mint(borrower.addr, 3);
            erc20s[1].mint(borrower.addr, 10000);
            vm.stopPrank();
        }
        conduitKeyOne = bytes32(uint256(uint160(address(this))) << 96);

        //    vm.startPrank(lender.addr);
        lenderConduit = conduitController.createConduit(conduitKeyOne, address(this));
        conduitController.updateChannel(lenderConduit, address(UO), true);
        erc20s[0].approve(address(lenderConduit), 100000);
        //    vm.stopPrank();
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
        newLoan();
    }

    function testRepayLoan() public {
        LoanManager.Loan memory activeLoan = newLoan();
        vm.startPrank(borrower.addr);
        erc20s[0].approve(address(consideration), 100000);
        vm.stopPrank();
        _executeRepayLoan(activeLoan);
    }

    ConsiderationItem[] collateral721;
    ConsiderationItem[] collateral20;
    SpentItem[] debt;

    function newLoan() internal returns (LoanManager.Loan memory) {
        UniqueOriginator.Details memory loanDetails;
        //    UniqueOriginator.Details memory loanDetails1;
        //    UniqueOriginator.Details memory loanDetails2;

        {
            FixedTermPricing pricing = new FixedTermPricing(LM);
            DutchAuctionHandler handler = new DutchAuctionHandler(LM);
            FixedTermHook hook = new FixedTermHook();

            collateral721.push(
                ConsiderationItem({
                    token: address(erc721s[0]),
                    startAmount: 1,
                    endAmount: 1,
                    identifierOrCriteria: 1,
                    itemType: ItemType.ERC721,
                    recipient: payable(LM.custodian())
                })
            );

            collateral20.push(
                ConsiderationItem({
                    token: address(erc20s[1]), //collateral token
                    startAmount: 100,
                    endAmount: 100,
                    identifierOrCriteria: 0,
                    itemType: ItemType.ERC20,
                    recipient: payable(LM.custodian())
                })
            );
            //      debt = new SpentItem[](1);
            debt.push(SpentItem({itemType: ItemType.ERC20, token: address(erc20s[0]), amount: 100, identifier: 0}));

            LoanManager.Terms memory terms = LoanManager.Terms({
                hook: address(hook),
                handler: address(handler),
                pricing: address(pricing),
                pricingData: abi.encode(
                    FixedTermPricing.Details({rate: uint256((uint256(1e16) / 365) * 1 days), loanDuration: 10 days})
                    ),
                handlerData: abi.encode(
                    DutchAuctionHandler.Details({startingPrice: uint256(500 ether), endingPrice: 100 wei, window: 7 days})
                    ),
                hookData: abi.encode(
                    FixedTermPricing.Details({rate: uint256((uint256(1e16) / 365) * 1 days), loanDuration: 10 days})
                    )
            });

            //      loanDetails1 = UniqueOriginator.Details({
            //        conduit: address(lenderConduit),
            //        issuer: address(this),
            //        deadline: block.timestamp + 100,
            //        terms: terms,
            //        collateral: ConsiderationItemLib.toSpentItemArray(collateral20),
            //        debt: SpentItem({
            //          itemType: ItemType.ERC20,
            //          token: address(erc20s[0]),
            //          amount: 100,
            //          identifier: 0
            //        })
            //      });
            UniqueOriginator.Details memory loanDetails = UniqueOriginator.Details({
                conduit: address(lenderConduit),
                issuer: address(this),
                deadline: block.timestamp + 100,
                terms: terms,
                collateral: ConsiderationItemLib.toSpentItemArray(collateral721),
                debt: debt[0]
            });
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(
                strategist.key,
                keccak256(UO.encodeWithAccountCounter(strategist.addr, keccak256(abi.encode(loanDetails))))
            );

            bool isTrusted = true;
            LoanManager.Loan memory loan = LoanManager.Loan({
                borrower: borrower.addr,
                originator: isTrusted ? address(UO) : address(0),
                terms: terms,
                debt: debt,
                collateral: ConsiderationItemLib.toSpentItemArray(collateral721),
                start: uint256(0)
            });
            return _executeNLR(
                loan,
                LoanManager.Obligation({
                    isTrusted: isTrusted,
                    ask: Originator.Request({
                        borrower: borrower.addr,
                        debt: debt,
                        details: abi.encode(loanDetails),
                        signature: abi.encodePacked(r, s, v)
                    }),
                    hash: keccak256(abi.encode(loan)),
                    originator: address(UO)
                }),
                collateral721
            );
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

    function _executeRepayLoan(LoanManager.Loan memory activeLoan) internal {
        uint256[] memory owing = Pricing(activeLoan.terms.pricing).getOwed(activeLoan);
        ReceivedItem[] memory loanPayment = Pricing(activeLoan.terms.pricing).getPaymentConsideration(activeLoan);
        uint256 i = 0;
        ConsiderationItem[] memory consider = new ConsiderationItem[](
      loanPayment.length
    );
        for (; i < loanPayment.length;) {
            consider[i].token = loanPayment[i].token;
            consider[i].itemType = loanPayment[i].itemType;
            consider[i].identifierOrCriteria = loanPayment[i].identifier;
            consider[i].startAmount = 5 ether; //TODO: update this
            consider[i].endAmount = 5 ether;
            consider[i].recipient = loanPayment[i].recipient;
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
        OrderParameters memory op = _buildContractOrder(address(LM.custodian()), repayOffering, consider);

        AdvancedOrder memory x = AdvancedOrder({
            parameters: op,
            numerator: 1,
            denominator: 1,
            signature: "0x",
            extraData: abi.encode(activeLoan)
        });

        uint256 balanceBefore = erc20s[0].balanceOf(borrower.addr);
        vm.recordLogs();
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

    //  function _matchNLR(
    //    LoanManager.Obligation memory nlr,
    //    ConsiderationItem[] memory collateral
    //  ) internal {
    //    //use murky to create a tree that is good
    //    //    CriteriaResolver[] memory resolver = new CriteriaResolver[](1);
    //
    //    //    Merkle memory merkle = Merkle({
    //    //      root: bytes32(0),
    //    //      leaves: new bytes32[](1),
    //    //      leafIndex: 0,
    //    //      leafCount: 1,
    //    //      depth: 0
    //    //    });
    //
    //    Originator.Response memory request = Originator(nlr.originator).build(
    //      Originator.ExecuteParams({
    //        borrower: nlr.request.borrower,
    //        loanRequestHash: nlr.request.hash,
    //        details: nlr.request.details,
    //        debt: nlr.request.debt,
    //        signature: nlr.request.signature
    //      })
    //    );
    //    OfferItem[] memory offerItem = new OfferItem[](1);
    //    offerItem[0] = OfferItem({
    //      itemType: ItemType.ERC721,
    //      token: address(LM),
    //      identifierOrCriteria: uint256(keccak256(abi.encode(request.loan))),
    //      startAmount: 1,
    //      endAmount: 1
    //    });
    //
    //    OrderParameters memory op = _buildContractOrder(
    //      address(LM),
    //      offerItem,
    //      collateral
    //    );
    //    bytes32 borrowerAskHash = consideration.getOrderHash(op);
    //    bytes memory signature = signOrder(consideration, borrower.key, orderHash);
    //
    //    AdvancedOrder memory x = AdvancedOrder({
    //      parameters: op,
    //      numerator: 1,
    //      denominator: 1,
    //      signature: signature,
    //      extraData: ""
    //    });
    //
    //    AdvancedOrder[] calldata orders = new AdvancedOrder[](2);
    //    orders[0] = x;
    //    orders[1] = y;
    //    //        CriteriaResolver[] calldata criteriaResolvers,
    //    //        Fulfillment[] calldata fulfillments,
    //    //        address recipient
    //
    //    uint256 balanceBefore = erc20s[0].balanceOf(borrower.addr);
    //    vm.recordLogs();
    //    vm.startPrank(borrower.addr);
    //    consideration.matchAdvancedOrders({
    //      advancedOrder: x,
    //      criteriaResolvers: new CriteriaResolver[](0),
    //      fulfillerConduitKey: bytes32(0),
    //      recipient: address(this)
    //    });
    //    //    Vm.Log[] memory logs = vm.getRecordedLogs();
    //
    //    uint256 balanceAfter = erc20s[0].balanceOf(borrower.addr);
    //
    //    vm.stopPrank();
    //  }

    function _executeNLR(
        LoanManager.Loan memory ask,
        LoanManager.Obligation memory nlr,
        ConsiderationItem[] memory collateral
    ) internal returns (LoanManager.Loan memory loan) {
        OfferItem[] memory offer = new OfferItem[](nlr.ask.debt.length + 1);
        offer[0] = OfferItem({
            itemType: ItemType.ERC721,
            token: address(LM),
            identifierOrCriteria: uint256(keccak256(abi.encode(ask))),
            startAmount: 1,
            endAmount: 1
        });
        uint256 i = 0;
        for (; i < debt.length;) {
            offer[i + 1] = OfferItem({
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
        OrderParameters memory op =
            _buildContractOrder(address(LM), nlr.isTrusted ? new OfferItem[](0) : offer, collateral);

        AdvancedOrder memory x =
            AdvancedOrder({parameters: op, numerator: 1, denominator: 1, signature: "0x", extraData: abi.encode(nlr)});

        uint256 balanceBefore = erc20s[0].balanceOf(borrower.addr);
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
        (loanId, loan) = abi.decode(logs[logs.length - (nlr.isTrusted ? 3 : 4)].data, (uint256, LoanManager.Loan));

        uint256 balanceAfter = erc20s[0].balanceOf(borrower.addr);

        assertEq(balanceAfter - balanceBefore, 100);
        vm.stopPrank();
    }
}
