pragma solidity =0.8.17;

import {LoanManager} from "src/LoanManager.sol";

import "src/originators/Originator.sol";
import {Custodian} from "src/Custodian.sol";
import {PoolHook} from "src/hooks/PoolHook.sol";
import {PoolPricing} from "src/pricing/PoolPricing.sol";

import {ItemType} from "seaport-types/src/lib/ConsiderationEnums.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";

contract PoolOriginator is Custodian, Originator {
  using FixedPointMathLib for uint256;
  error InvalidDetailsProvided();
  constructor(
    LoanManager LM_,
    address seaport,
    address strategist_,
    uint256 fee_
  ) Custodian(LM_, seaport) Originator(LM_, strategist_, fee_) {}

  struct Details {
    address custodian;
    address conduit;
    address issuer;
    uint256 deadline;
    LoanManager.Terms terms;
    SpentItem[] collateral;
    SpentItem[] debt;
  }
  address conduit;

  address pricing;
  address hook;
  address handler;

  uint256 duration;

  address token_x;
  address token_y;
  // custodian is self (we are gonig to relend their collateral)
  uint256 reserve_x;
  uint256 reserve_y;
  
  // reserve_x * reserve_y = k
  // (reserve_x + change in x) / k = reserve_y

  function _quote(uint256 amount, uint256 a, uint256 b) pure internal returns (uint256 price, uint256 impactPrice){
    price = _quotePrice(a, b);
    impactPrice = price - _quoteImpactPrice(amount, a, b);
  }
  function _quotePrice(uint256 numerator, uint256 denominator) pure internal returns (uint256 quote){
    return numerator.divWad(denominator);
  }
  function _quoteImpactPrice(uint256 amount, uint256 a, uint256 b) pure internal returns (uint256 quote){
    uint256 k = a * b;
    uint256 reserve_a_virtual = a + amount;
    uint256 reserve_b_virtual = reserve_a_virtual.divWad(k);
    return reserve_a_virtual.divWad(reserve_b_virtual);
  }

  // colalteralize x -> borrow y
  // function borrowY(uint256 amount) {
  //   _generateDetails(amount, reserve_y, token_y, reserve_x, token_x);
  // }

  function generateDetails(uint256 amount, uint256 reserve_a, address token_a, uint256 reserve_b, address token_b) public returns (Details memory details){
    (uint256 price, uint256 impactPrice) = _quote(amount, reserve_a, reserve_b);
    SpentItem[] memory collateral = new SpentItem[](1);
    collateral[0] = SpentItem({
      itemType: ItemType.ERC20,
      token: token_a,
      identifier: 0,
      amount: amount
    });
    SpentItem[] memory debt = new SpentItem[](1);
    debt[0] = SpentItem({
      itemType: ItemType.ERC20,
      token: token_b,
      identifier: 0,
      amount: amount * impactPrice
    });

    LoanManager.Terms memory terms = LoanManager.Terms({
      hook: hook,
      hookData: abi.encode(PoolHook.Details({
        duration: duration
      })),
      pricing: pricing,
      pricingData: abi.encode(PoolPricing.Details({
        deltaPrice: price - impactPrice
      })),
      handler: handler,
      handlerData: new bytes(0)
    });

    details = Details({
      custodian: address(this),
      conduit: conduit,
      issuer: address(this),
      deadline: 0,
      terms: terms,
      collateral: collateral,
      debt: debt
    });
  }

  function _build(
    Request calldata params,
    Details memory details
  ) internal view returns (Response memory response) {
    bool needsMint = details.issuer.code.length > 0;
    response = Response({terms: details.terms, issuer: details.issuer});
  }

  function execute(
    Request calldata params
  ) external override returns (Response memory response) {
    _validateAsk(params);
    Details memory details = abi.decode(params.details, (Details));
    if (
      ConduitInterface(details.conduit).execute(
        _packageTransfers(params.debt, params.receiver, details.issuer)
      ) != ConduitInterface.execute.selector
    ) {
      revert ConduitTransferError();
    }

    response = _build(params, details);
  }

  function _validateAsk(
    Request memory request
  ) internal {
    Details memory details = abi.decode(request.details, (Details));

    Details memory generatedDetails;
    // check which direction they are borrowing
    // colalteralizing x -> borrowing y
    if(details.collateral[0].token == token_x){
      generatedDetails = generateDetails(details.collateral[0].amount, reserve_x, token_x, reserve_y, token_y);

    }
    // colalteralizing y -> borrowing x
    else if(details.collateral[0].token == token_y){
      generatedDetails = generateDetails(details.collateral[0].amount, reserve_y, token_y, reserve_x, token_x);
    }
    // very biblical but skips a bunch of checks (add something for slippage later)
    // if(abi.encode(generatedDetails) != request.details) revert InvalidDetailsProvided();
  }

  function getFeeConsideration(
    LoanManager.Loan calldata loan
  ) external view override virtual returns (ReceivedItem[] memory consideration){
    return new ReceivedItem[](0);
  }

  function terms(
    bytes calldata details
  ) public view override returns (LoanManager.Terms memory) {
    return abi.decode(details, (Details)).terms;
  }
}
