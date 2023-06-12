pragma solidity =0.8.17;

import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

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
import {Conduit} from "seaport-core/src/conduit/Conduit.sol";
import {
  ConduitController
} from "seaport-core/src/conduit/ConduitController.sol";
import {Consideration} from "seaport-core/src/lib/Consideration.sol";
import {UniqueOriginator} from "src/originators/UniqueOriginator.sol";
import {FixedTermPricing} from "src/pricing/FixedTermPricing.sol";
import {FixedTermHook} from "src/hooks/FixedTermHook.sol";
import {DutchAuctionHandler} from "src/handlers/DutchAuctionHandler.sol";

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

contract TestStarLite is BaseOrderTest {
  //    address conduit;
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

    LM = new LoanManager(ConsiderationInterface(address(consideration)));
    UO = new UniqueOriginator(
      LM,
      ConduitControllerInterface(address(conduitController)),
      strategist.addr,
      1e16
    );

    conduitKeyOne = bytes32(uint256(uint160(address(lender.addr))) << 96);

    vm.startPrank(lender.addr);
    lenderConduit = conduitController.createConduit(
      conduitKeyOne,
      address(lender.addr)
    );
    conduitController.updateChannel(lenderConduit, address(UO), true);
    erc20s[0].approve(address(UO.conduit()), 100000);
    vm.stopPrank();
  }

  function onERC721Received(
    address operator,
    address from,
    uint256 tokenId,
    bytes calldata data
  ) public pure override returns (bytes4) {
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

  function newLoan() internal returns (LoanManager.Loan memory activeLoan) {
    TestERC721 nft = erc721s[0];

    TestERC20 debtToken = erc20s[0];
    vm.label(address(debtToken), "what");
    {
      vm.startPrank(borrower.addr);
      nft.mint(borrower.addr, 1);
      //      nft.setApprovalForAll(address(consideration), true);
      vm.stopPrank();
    }

    //        UniqueOriginator.Details memory loanDetails = UniqueOriginator.Details({
    //            validator: address(UO),
    //            conduit: address(conduit),
    //            collateral: address(nft),
    //            debtToken: address(debtToken),
    //            identifier: 1,
    //            maxAmount: 100,
    //            rate: 1,
    //            loanDuration: 1000,
    //            deadline: block.timestamp + 100,
    //            settlement: UniqueOriginator.SettlementData({startingPrice: uint(500 ether), endingPrice: 100 wei, window: 7 days})
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

    UniqueOriginator.Details memory loanDetails;

    {
      FixedTermPricing pricing = new FixedTermPricing(LM);
      DutchAuctionHandler handler = new DutchAuctionHandler();
      FixedTermHook hook = new FixedTermHook();
      loanDetails = UniqueOriginator.Details({
        originator: address(UO),
        hook: address(hook),
        handler: address(handler),
        pricing: address(pricing),
        deadline: block.timestamp + 100,
        collateral: SpentItem({
          token: address(nft),
          amount: 1,
          identifier: 0,
          itemType: ItemType.ERC721
        }),
        debt: ReceivedItem({
          recipient: payable(lender.addr),
          token: address(erc20s[0]),
          amount: 100,
          identifier: 0,
          itemType: ItemType.ERC20
        }),
        pricingData: abi.encode(
          FixedTermPricing.Details({
            rate: uint256((uint256(1e16) / 365) * 1 days),
            loanDuration: 10 days
          })
        ),
        handlerData: abi.encode(
          DutchAuctionHandler.Details({
            startingPrice: uint256(500 ether),
            endingPrice: 100 wei,
            window: 7 days
          })
        ),
        hookData: abi.encode(
          FixedTermPricing.Details({
            rate: uint256((uint256(1e16) / 365) * 1 days),
            loanDuration: 10 days
          })
        )
      });
    }

    bytes32 hash = keccak256(
      UO.encodeWithAccountCounter(strategist.addr, abi.encode(loanDetails))
    );
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(strategist.key, hash);

    activeLoan = _executeNLR(
      LoanManager.NewLoanRequest({
        details: abi.encode(loanDetails),
        loan: LoanManager.Loan({
          collateral: SpentItem({
            token: address(erc721s[0]),
            amount: 1,
            identifier: 1,
            itemType: ItemType.ERC721
          }),
          debt: ReceivedItem({
            recipient: payable(borrower.addr),
            token: address(debtToken),
            amount: 100,
            identifier: 0,
            itemType: ItemType.ERC20
          }),
          originator: loanDetails.originator,
          hook: loanDetails.hook,
          handler: loanDetails.handler,
          pricing: loanDetails.pricing,
          pricingData: abi.encode(
            FixedTermPricing.Details({
              rate: uint256((uint256(1e16) / 365) * 1 days),
              loanDuration: 10 days
            })
          ),
          handlerData: abi.encode(
            DutchAuctionHandler.Details({
              startingPrice: uint256(500 ether),
              endingPrice: 100 wei,
              window: 7 days
            })
          ),
          hookData: abi.encode(
            FixedTermPricing.Details({
              rate: uint256((uint256(1e16) / 365) * 1 days),
              loanDuration: 10 days
            })
          ),
          start: uint256(0),
          nonce: uint256(0)
        }),
        signature: Originator.Signature({v: v, r: r, s: s})
      })
    );
  }

  function _buildLMContractOrder(
    OfferItem[] memory offer,
    ConsiderationItem[] memory consider
  ) internal view returns (OrderParameters memory op) {
    op = OrderParameters({
      offerer: address(LM),
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
    uint256 owing = Pricing(activeLoan.pricing).getOwed(activeLoan);
    ConsiderationItem[] memory consider = new ConsiderationItem[](1);
    ReceivedItem memory loanPayment = Pricing(activeLoan.pricing)
      .getPaymentConsideration(activeLoan);
    consider[0] = ConsiderationItem({
      itemType: loanPayment.itemType,
      token: address(loanPayment.token),
      identifierOrCriteria: loanPayment.identifier,
      startAmount: 5 ether,
      endAmount: 5 ether,
      recipient: loanPayment.recipient
    });
    OfferItem[] memory repayOffering = new OfferItem[](1);
    repayOffering[0] = OfferItem({
      itemType: activeLoan.collateral.itemType,
      token: address(activeLoan.collateral.token),
      identifierOrCriteria: activeLoan.collateral.identifier,
      endAmount: activeLoan.collateral.itemType != ItemType.ERC721
        ? activeLoan.collateral.amount
        : 1,
      startAmount: activeLoan.collateral.itemType != ItemType.ERC721
        ? activeLoan.collateral.amount
        : 1
    });
    OrderParameters memory op = _buildLMContractOrder(repayOffering, consider);

    AdvancedOrder memory x = AdvancedOrder({
      parameters: op,
      numerator: 1,
      denominator: 1,
      signature: "0x",
      extraData: abi.encode(uint8(LoanManager.Action.UNLOCK), activeLoan)
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
    Vm.Log[] memory logs = vm.getRecordedLogs();

    uint256 balanceAfter = erc20s[0].balanceOf(borrower.addr);

    //    assertEq(balanceAfter - balanceBefore, 100);
    vm.stopPrank();
  }

  function _executeNLR(
    LoanManager.NewLoanRequest memory nlr
  ) internal returns (LoanManager.Loan memory loan) {
    ConsiderationItem[] memory consider = new ConsiderationItem[](1);
    consider[0] = ConsiderationItem({
      itemType: ItemType.ERC721,
      token: address(erc721s[0]),
      identifierOrCriteria: 1,
      startAmount: 1,
      endAmount: 1,
      recipient: payable(address(LM))
    });
    OrderParameters memory op = _buildLMContractOrder(
      new OfferItem[](0),
      consider
    );

    LoanManager.NewLoanRequest[] memory nlrs = new LoanManager.NewLoanRequest[](
      1
    );
    nlrs[0] = nlr;

    AdvancedOrder memory x = AdvancedOrder({
      parameters: op,
      numerator: 1,
      denominator: 1,
      signature: "0x",
      extraData: abi.encode(uint8(LoanManager.Action.LOCK), nlrs)
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
    Vm.Log[] memory logs = vm.getRecordedLogs();
    loan = abi.decode(logs[logs.length - 2].data, (LoanManager.Loan));

    uint256 balanceAfter = erc20s[0].balanceOf(borrower.addr);

    assertEq(balanceAfter - balanceBefore, 100);
    vm.stopPrank();
  }
}
