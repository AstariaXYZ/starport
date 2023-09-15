import "./StarPortTest.sol";
import {AstariaV1Pricing} from "src/pricing/AstariaV1Pricing.sol";

contract TestNewLoan is StarPortTest {
  function testNewLoanERC721CollateralDefaultTerms2()
    public
    returns (LoanManager.Loan memory)
  {
    Custodian custody = Custodian(LM.defaultCustodian());

    LoanManager.Terms memory terms = LoanManager.Terms({
      hook: address(hook),
      handler: address(handler),
      pricing: address(pricing),
      pricingData: defaultPricingData,
      handlerData: defaultHandlerData,
      hookData: defaultHookData
    });

    selectedCollateral.push(
      ConsiderationItem({
        token: address(erc721s[0]),
        startAmount: 1,
        endAmount: 1,
        identifierOrCriteria: 1,
        itemType: ItemType.ERC721,
        recipient: payable(address(custody))
      })
    );

    debt.push(
      SpentItem({
        itemType: ItemType.ERC20,
        token: address(erc20s[0]),
        amount: 100,
        identifier: 0
      })
    );
    UniqueOriginator.Details memory loanDetails = UniqueOriginator.Details({
      conduit: address(lenderConduit),
      custodian: address(custody),
      issuer: lender.addr,
      deadline: block.timestamp + 100,
      terms: terms,
      collateral: ConsiderationItemLib.toSpentItemArray(selectedCollateral),
      debt: debt
    });
    bool isTrusted = true;

    TermEnforcer TE = new TermEnforcer();

    TermEnforcer.Details memory TEDetails = TermEnforcer.Details({
      pricing: address(pricing),
      hook: address(hook),
      handler: address(handler)
    });

    LoanManager.Caveat[] memory caveats = new LoanManager.Caveat[](1);
    caveats[0] = LoanManager.Caveat({
      enforcer: address(TE),
      terms: abi.encode(TEDetails)
    });

    return
      newLoan(
        NewLoanData(address(custody), caveats, abi.encode(loanDetails)),
        Originator(UO),
        selectedCollateral
      );
  }

  function testNewLoanERC721CollateralDefaultTermsRefinance() public {
    Custodian custody = Custodian(LM.defaultCustodian());

    //    pricing = new AstariaV1Pricing(LM);
    LoanManager.Terms memory terms = LoanManager.Terms({
      hook: address(hook),
      handler: address(handler),
      pricing: address(pricing),
      pricingData: defaultPricingData,
      handlerData: defaultHandlerData,
      hookData: defaultHookData
    });

    selectedCollateral.push(
      ConsiderationItem({
        token: address(erc721s[0]),
        startAmount: 1,
        endAmount: 1,
        identifierOrCriteria: 1,
        itemType: ItemType.ERC721,
        recipient: payable(address(custody))
      })
    );

    debt.push(
      SpentItem({
        itemType: ItemType.ERC20,
        token: address(erc20s[0]),
        amount: 100,
        identifier: 0
      })
    );
    UniqueOriginator.Details memory loanDetails = UniqueOriginator.Details({
      conduit: address(lenderConduit),
      custodian: address(custody),
      issuer: lender.addr,
      deadline: block.timestamp + 100,
      terms: terms,
      collateral: ConsiderationItemLib.toSpentItemArray(selectedCollateral),
      debt: debt
    });
    bool isTrusted = true;

    LoanManager.Loan memory loan = newLoan(
      NewLoanData(
        address(custody),
        new LoanManager.Caveat[](0),
        abi.encode(loanDetails)
      ),
      Originator(UO),
      selectedCollateral
    );
    vm.startPrank(refinancer.addr);
    LM.refinance(
      loan,
      abi.encode(
        BasePricing.Details({
          rate: (uint256(1e16) * 100) / (365 * 1 days),
          carryRate: 0
        })
      ),
      refinancerConduit
    );
    vm.stopPrank();
  }

  function testNewLoanERC721CollateralDefaultTermsWithMerkleProof()
    public
    returns (LoanManager.Loan memory)
  {
    Custodian custody = Custodian(LM.defaultCustodian());

    LoanManager.Terms memory terms = LoanManager.Terms({
      hook: address(hook),
      handler: address(handler),
      pricing: address(pricing),
      pricingData: defaultPricingData,
      handlerData: defaultHandlerData,
      hookData: defaultHookData
    });

    selectedCollateral.push(
      ConsiderationItem({
        token: address(erc721s[0]),
        startAmount: 1,
        endAmount: 1,
        identifierOrCriteria: 1,
        itemType: ItemType.ERC721,
        recipient: payable(address(custody))
      })
    );

    debt.push(
      SpentItem({
        itemType: ItemType.ERC20,
        token: address(erc20s[0]),
        amount: 100,
        identifier: 0
      })
    );
    //need to add1
    //address custodian;
    //    address conduit;
    //    address issuer;
    //    uint256 deadline;
    //    LoanManager.Terms terms;
    //    SpentItem[] collateral;
    //    SpentItem[] debt;
    //    bytes validator;
    MerkleOriginator.Details memory loanDetails = MerkleOriginator.Details({
      custodian: address(custody),
      conduit: address(CP.conduit()),
      issuer: address(CP),
      deadline: block.timestamp + 100,
      terms: terms,
      collateral: ConsiderationItemLib.toSpentItemArray(selectedCollateral),
      debt: debt,
      validator: bytes("0x")
    });
    bytes32 leafHash = keccak256(
      abi.encode(
        loanDetails.custodian,
        loanDetails.conduit,
        loanDetails.issuer,
        loanDetails.deadline,
        loanDetails.terms,
        loanDetails.collateral,
        loanDetails.debt
      )
    );
    loanDetails.validator = abi.encode(
      MerkleOriginator.MerkleProof({root: leafHash, proof: new bytes32[](0)})
    );

    return
      newLoanWithMerkleProof(
        NewLoanData(
          address(custody),
          new LoanManager.Caveat[](0),
          abi.encode(loanDetails)
        ),
        Originator(MO),
        selectedCollateral
      );
  }

  function testBuyNowPayLater() public {
    ConsiderationItem[] memory want = new ConsiderationItem[](1);
    want[0] = ConsiderationItem({
      token: address(erc20s[0]),
      startAmount: 150,
      endAmount: 150,
      identifierOrCriteria: 0,
      itemType: ItemType.ERC20,
      recipient: payable(seller.addr)
    });

    //order 1, which lets is the selller, they have something that we can borrower againt (ERC721)
    //order 2 which is the

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
    bytes32 sellingHash = consideration.getOrderHash(
      OrderParametersLib.toOrderComponents(thingToSell, 0)
    );
    (bytes32 r, bytes32 s, uint8 v) = getSignatureComponents(
      consideration,
      seller.key,
      sellingHash
    );

    AdvancedOrder memory advThingToSell = AdvancedOrder({
      parameters: thingToSell,
      numerator: 1,
      denominator: 1,
      signature: abi.encodePacked(r, s, v),
      extraData: ""
    });

    Custodian custody = Custodian(LM.defaultCustodian());

    LoanManager.Terms memory terms = LoanManager.Terms({
      hook: address(hook),
      handler: address(handler),
      pricing: address(pricing),
      pricingData: defaultPricingData,
      handlerData: defaultHandlerData,
      hookData: defaultHookData
    });

    selectedCollateral.push(
      ConsiderationItem({
        token: address(erc721s[1]),
        startAmount: 1,
        endAmount: 1,
        identifierOrCriteria: 1,
        itemType: ItemType.ERC721,
        recipient: payable(address(custody))
      })
    );

    debt.push(
      SpentItem({
        itemType: ItemType.ERC20,
        token: address(erc20s[0]),
        amount: 100,
        identifier: 0
      })
    );
    UniqueOriginator.Details memory loanDetails = UniqueOriginator.Details({
      conduit: address(lenderConduit),
      custodian: address(custody),
      issuer: lender.addr,
      deadline: block.timestamp + 100,
      terms: terms,
      collateral: ConsiderationItemLib.toSpentItemArray(selectedCollateral),
      debt: debt
    });

    TermEnforcer TE = new TermEnforcer();

    TermEnforcer.Details memory TEDetails = TermEnforcer.Details({
      pricing: address(pricing),
      hook: address(hook),
      handler: address(handler)
    });

    LoanManager.Caveat[] memory caveats = new LoanManager.Caveat[](1);
    caveats[0] = LoanManager.Caveat({
      enforcer: address(TE),
      terms: abi.encode(TEDetails)
    });

    buyNowPayLater(
      advThingToSell,
      NewLoanData(address(custody), caveats, abi.encode(loanDetails)),
      Originator(UO),
      selectedCollateral
    );
  }

  function testSettleLoan() public {
    //default is 14 day term
    LoanManager.Loan
      memory activeLoan = testNewLoanERC721CollateralDefaultTerms2();

    skip(14 days);

    minimumReceived.push(
      SpentItem({
        itemType: ItemType.ERC20,
        token: address(erc20s[0]),
        amount: 600 ether,
        identifier: 0
      })
    );
    (
      ReceivedItem[] memory settlementConsideration,
      address restricted
    ) = SettlementHandler(activeLoan.terms.handler).getSettlement(activeLoan);

    ConsiderationItem[] memory consider = new ConsiderationItem[](
      settlementConsideration.length
    );
    uint i = 0;
    for (; i < settlementConsideration.length; ) {
      consider[i].token = settlementConsideration[i].token;
      consider[i].itemType = settlementConsideration[i].itemType;
      consider[i].identifierOrCriteria = settlementConsideration[i].identifier;
      consider[i].startAmount = settlementConsideration[i].amount;
      //TODO: update this
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
      address(activeLoan.custodian),
      repayOffering,
      consider
    );
    if (restricted == address(0)) {
      AdvancedOrder memory settlementOrder = AdvancedOrder({
        numerator: 1,
        denominator: 1,
        parameters: op,
        extraData: abi.encode(activeLoan),
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
}
