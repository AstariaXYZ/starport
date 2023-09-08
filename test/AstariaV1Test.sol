pragma solidity =0.8.17;

import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {CapitalPool} from "src/CapitalPool.sol";
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
import {
  OrderParametersLib
} from "seaport/lib/seaport-sol/src/lib/OrderParametersLib.sol";
import {
  ConduitTransfer,
  ConduitItemType
} from "seaport-types/src/conduit/lib/ConduitStructs.sol";
import {
  ConsiderationInterface
} from "seaport-types/src/interfaces/ConsiderationInterface.sol";
import {
  ConsiderationItem,
  AdvancedOrder,
  CriteriaResolver,
  Fulfillment,
  FulfillmentComponent,
  OrderType
} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {Conduit} from "seaport-core/src/conduit/Conduit.sol";
import {
  ConduitController
} from "seaport-core/src/conduit/ConduitController.sol";
import {Consideration} from "seaport-core/src/lib/Consideration.sol";
//import {
//  ReferenceConsideration as Consideration
//} from "seaport/reference/ReferenceConsideration.sol";
import {UniqueOriginator} from "src/originators/UniqueOriginator.sol";
import {MerkleOriginator} from "src/originators/MerkleOriginator.sol";
import {SimpleInterestPricing} from "src/pricing/SimpleInterestPricing.sol";
import {BasePricing} from "src/pricing/BasePricing.sol";
import {FixedTermHook} from "src/hooks/FixedTermHook.sol";
import {DutchAuctionHandler} from "src/handlers/DutchAuctionHandler.sol";
import {EnglishAuctionHandler} from "src/handlers/EnglishAuctionHandler.sol";
import {Merkle} from "seaport/lib/murky/src/Merkle.sol";

import {BaseOrderTest} from "seaport/test/foundry/utils/BaseOrderTest.sol";
import {TestERC721} from "seaport/contracts/test/TestERC721.sol";
import {TestERC20} from "seaport/contracts/test/TestERC20.sol";
import {
  ConsiderationItemLib
} from "seaport/lib/seaport-sol/src/lib/ConsiderationItemLib.sol";
import {Custodian} from "src/Custodian.sol";
import "../src/custodians/AAVEPoolCustodian.sol";
import "seaport/lib/seaport-sol/src/lib/AdvancedOrderLib.sol";

import {TermEnforcer} from "src/enforcers/TermEnforcer.sol";

interface IWETH9 {
  function deposit() external payable;

  function withdraw(uint256) external;
}

contract StarPortTest is BaseOrderTest {
  Pricing pricing;
  SettlementHandler handler;
  SettlementHook hook;

  uint256 defaultLoanDuration = 14 days;

  // 1% interest rate per second
  bytes defaultPricingData =
    abi.encode(
      BasePricing.Details({
        carryRate: (uint256(1e16) * 10),
        rate: (uint256(1e16) * 150) / (365 * 1 days)
      })
    );

  bytes defaultHandlerData =
    abi.encode(
      DutchAuctionHandler.Details({
        startingPrice: uint256(500 ether),
        endingPrice: 100 wei,
        window: 7 days
      })
    );
  bytes defaultHookData =
    abi.encode(FixedTermHook.Details({loanDuration: defaultLoanDuration}));

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
  MerkleOriginator MO;

  CapitalPool CP;

  bytes32 conduitKeyRefinancer;

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
    seller = makeAndAllocateAccount("seller");
    refinancer = makeAndAllocateAccount("refinancer");

    LM = new LoanManager();
    custodian = new Custodian(LM, address(consideration));
    UO = new UniqueOriginator(LM, strategist.addr, 1e16);
    MO = new MerkleOriginator(LM, strategist.addr, 1e16);
    CP = new CapitalPool(address(erc20s[0]), conduitController, address(MO));
    pricing = new SimpleInterestPricing(LM);
    handler = new DutchAuctionHandler(LM);
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
    conduitKeyRefinancer = bytes32(
      uint256(uint160(address(refinancer.addr))) << 96
    );

    vm.startPrank(lender.addr);
    erc20s[0].approve(address(CP), 10 ether);
    CP.deposit(10 ether, lender.addr);
    lenderConduit = conduitController.createConduit(conduitKeyOne, lender.addr);

    conduitController.updateChannel(lenderConduit, address(UO), true);
    conduitController.updateChannel(lenderConduit, address(MO), true);
    erc20s[0].approve(address(lenderConduit), 100000);
    vm.stopPrank();
    vm.startPrank(refinancer.addr);
    refinancerConduit = conduitController.createConduit(
      conduitKeyRefinancer,
      refinancer.addr
    );
    console.log("Refinancer", refinancer.addr);
    conduitController.updateChannel(refinancerConduit, address(LM), true);
    erc20s[0].approve(address(refinancerConduit), 100000);
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

  ConsiderationItem[] selectedCollateral;
  ConsiderationItem[] collateral20;
  SpentItem[] debt;

  struct NewLoanData {
    address custodian;
    LoanManager.Caveat[] caveats;
    bytes details;
  }

  function newLoan(
    NewLoanData memory loanData,
    Originator originator,
    ConsiderationItem[] storage collateral
  ) internal returns (LoanManager.Loan memory) {
    bool isTrusted = loanData.caveats.length == 0;
    {
      (uint8 v, bytes32 r, bytes32 s) = vm.sign(
        strategist.key,
        keccak256(
          originator.encodeWithAccountCounter(
            strategist.addr,
            keccak256(loanData.details)
          )
        )
      );

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
      return
        _executeNLR(
          LoanManager.Obligation({
            custodian: address(loanData.custodian),
            borrower: borrower.addr,
            debt: debt,
            salt: bytes32(0),
            details: loanData.details,
            signature: abi.encodePacked(r, s, v),
            caveats: loanData.caveats,
            originator: address(originator)
          }),
          collateral // for building contract offer
        );
    }
  }

  function newLoanWithMerkleProof(
    NewLoanData memory loanData,
    Originator originator,
    ConsiderationItem[] storage collateral
  ) internal returns (LoanManager.Loan memory) {
    bool isTrusted = loanData.caveats.length == 0;
    {
      MerkleOriginator.Details memory details = abi.decode(
        loanData.details,
        (MerkleOriginator.Details)
      );
      MerkleOriginator.MerkleProof memory merkleData = abi.decode(
        details.validator,
        (MerkleOriginator.MerkleProof)
      );
      (uint8 v, bytes32 r, bytes32 s) = vm.sign(
        strategist.key,
        keccak256(
          originator.encodeWithAccountCounter(strategist.addr, merkleData.root)
        )
      );

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
      return
        _executeNLR(
          LoanManager.Obligation({
            custodian: address(loanData.custodian),
            borrower: borrower.addr,
            debt: debt,
            salt: bytes32(0),
            details: loanData.details,
            signature: abi.encodePacked(r, s, v),
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
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(
      strategist.key,
      keccak256(
        originator.encodeWithAccountCounter(
          strategist.addr,
          keccak256(loanData.details)
        )
      )
    );

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
        signature: abi.encodePacked(r, s, v),
        caveats: loanData.caveats,
        originator: address(originator)
      }),
      collateral // for building contract offer
    );
  }

  function _buildContractOrder(
    address offerer,
    OfferItem[] memory offer,
    ConsiderationItem[] memory consider
  ) internal view returns (OrderParameters memory op) {
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
    (
      ReceivedItem[] memory loanPayment,
      ReceivedItem[] memory carryPayment
    ) = Pricing(activeLoan.terms.pricing).getPaymentConsideration(activeLoan);
    uint256 i = 0;
    ConsiderationItem[] memory consider = new ConsiderationItem[](
      loanPayment.length + carryPayment.length
    );
    for (; i < loanPayment.length; ) {
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
    for (; i < carryPayment.length; ) {
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
    for (; i < activeLoan.collateral.length; ) {
      repayOffering[i] = OfferItem({
        itemType: activeLoan.collateral[i].itemType,
        token: address(activeLoan.collateral[i].token),
        identifierOrCriteria: activeLoan.collateral[i].identifier,
        endAmount: activeLoan.collateral[i].itemType != ItemType.ERC721
          ? activeLoan.collateral[i].amount
          : 1,
        startAmount: activeLoan.collateral[i].itemType != ItemType.ERC721
          ? activeLoan.collateral[i].amount
          : 1
      });
      unchecked {
        ++i;
      }
    }
    OrderParameters memory op = _buildContractOrder(
      address(custodian),
      repayOffering,
      consider
    );

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

  function _buyNowPLNLR(
    AdvancedOrder memory x,
    //    LoanManager.Loan memory loanAsk,
    LoanManager.Obligation memory nlr,
    ConsiderationItem[] memory collateral // collateral (nft) and weth (purchase price is incoming weth plus debt)
  ) internal returns (LoanManager.Loan memory loan) {
    //use murky to create a tree that is good

    bytes32 caveatHash = keccak256(
      LM.encodeWithSaltAndBorrowerCounter(
        nlr.borrower,
        nlr.salt,
        keccak256(abi.encode(nlr.caveats))
      )
    );
    OfferItem[] memory offer = new OfferItem[](nlr.debt.length + 1);
    offer[0] = OfferItem({
      itemType: ItemType.ERC721,
      token: address(LM),
      identifierOrCriteria: uint256(caveatHash),
      startAmount: 1,
      endAmount: 1
    });
    uint256 i = 0;
    for (; i < debt.length; ) {
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

    OfferItem[] memory zOffer = new OfferItem[](1);
    zOffer[0] = OfferItem({
      itemType: nlr.debt[0].itemType,
      token: nlr.debt[0].token,
      identifierOrCriteria: nlr.debt[0].identifier,
      startAmount: x.parameters.consideration[0].startAmount -
        nlr.debt[0].amount,
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
    AdvancedOrder memory z = AdvancedOrder({
      parameters: zOP,
      numerator: 1,
      denominator: 1,
      signature: "",
      extraData: ""
    });

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

    fill[0].offerComponents[0] = FulfillmentComponent({
      orderIndex: 1,
      itemIndex: 1
    });
    fill[0].considerationComponents[0] = FulfillmentComponent({
      orderIndex: 0,
      itemIndex: 0
    });
    fill[1] = Fulfillment({
      offerComponents: new FulfillmentComponent[](1),
      considerationComponents: new FulfillmentComponent[](1)
    });

    fill[1].offerComponents[0] = FulfillmentComponent({
      orderIndex: 2,
      itemIndex: 0
    });
    fill[1].considerationComponents[0] = FulfillmentComponent({
      orderIndex: 0,
      itemIndex: 0
    });

    fill[2] = Fulfillment({
      offerComponents: new FulfillmentComponent[](1),
      considerationComponents: new FulfillmentComponent[](1)
    });

    fill[2].offerComponents[0] = FulfillmentComponent({
      orderIndex: 0,
      itemIndex: 0
    });
    fill[2].considerationComponents[0] = FulfillmentComponent({
      orderIndex: 1,
      itemIndex: 0
    });
    fill[3] = Fulfillment({
      offerComponents: new FulfillmentComponent[](1),
      considerationComponents: new FulfillmentComponent[](1)
    });

    fill[3].offerComponents[0] = FulfillmentComponent({
      orderIndex: 1,
      itemIndex: 0
    });
    fill[3].considerationComponents[0] = FulfillmentComponent({
      orderIndex: 2,
      itemIndex: 0
    });

    uint256 balanceBefore = erc20s[0].balanceOf(seller.addr);
    vm.recordLogs();
    vm.startPrank(borrower.addr);

    consideration.matchAdvancedOrders(
      orders,
      new CriteriaResolver[](0),
      fill,
      address(borrower.addr)
    );

    (, loan) = abi.decode(
      vm.getRecordedLogs()[debt.length + 1].data,
      (uint256, LoanManager.Loan)
    );

    assertEq(erc721s[1].ownerOf(1), address(nlr.custodian));
    assertEq(
      erc20s[0].balanceOf(seller.addr),
      balanceBefore + x.parameters.consideration[0].startAmount
    );
    vm.stopPrank();
  }

  function _executeNLR(
    LoanManager.Obligation memory nlr,
    ConsiderationItem[] memory collateral
  ) internal returns (LoanManager.Loan memory loan) {
    bytes32 caveatHash = keccak256(
      LM.encodeWithSaltAndBorrowerCounter(
        nlr.borrower,
        nlr.salt,
        keccak256(abi.encode(nlr.caveats))
      )
    );
    OfferItem[] memory offer = new OfferItem[](nlr.debt.length + 1);
    offer[0] = OfferItem({
      itemType: ItemType.ERC721,
      token: address(LM),
      identifierOrCriteria: uint256(caveatHash),
      startAmount: 1,
      endAmount: 1
    });
    uint256 i = 0;
    for (; i < debt.length; ) {
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
    OrderParameters memory op = _buildContractOrder(
      address(LM),
      nlr.caveats.length == 0 ? new OfferItem[](0) : offer,
      collateral
    );

    AdvancedOrder memory x = AdvancedOrder({
      parameters: op,
      numerator: 1,
      denominator: 1,
      signature: "0x",
      extraData: abi.encode(nlr)
    });

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

    //    console.logBytes32(logs[logs.length - 4].topics[0]);
    bytes32 lienOpenTopic = bytes32(
      0x57cb72d73c48fadf55428537f6c9efbe080ae111339b0c5af42d9027ed20ba17
    );
    for (uint i = 0; i < logs.length; i++) {
      if (logs[i].topics[0] == lienOpenTopic) {
        (loanId, loan) = abi.decode(logs[i].data, (uint256, LoanManager.Loan));
        break;
      }
    }

    uint256 balanceAfter = erc20s[0].balanceOf(borrower.addr);

    assertEq(balanceAfter - balanceBefore, debt[0].amount);
    vm.stopPrank();
  }
}