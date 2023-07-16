import "./StarPortTest.sol";

contract TestNewLoan is StarPortTest {
  function testNewLoanERC721CollateralDefaultTerms()
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

    return
      newLoan(
        NewLoanData(address(custody), isTrusted, abi.encode(loanDetails)),
        Originator(UO),
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
    bool isTrusted = false;

    buyNowPayLater(
      advThingToSell,
      NewLoanData(address(custody), isTrusted, abi.encode(loanDetails)),
      Originator(UO),
      selectedCollateral
    );
  }

  function testSettleLoan() public {
    //default is 14 day term
    LoanManager.Loan
      memory activeLoan = testNewLoanERC721CollateralDefaultTerms();

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
