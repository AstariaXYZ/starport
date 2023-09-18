pragma solidity =0.8.17;

import {LoanManager} from "src/LoanManager.sol";

import "src/originators/BaseOriginator.sol";
import {MerkleProofLib} from "solady/src/utils/MerkleProofLib.sol";
import "forge-std/console.sol";

contract MerkleOriginator is BaseOriginator {
  error InvalidMerkleProof();

  constructor(
    LoanManager LM_,
    address strategist_,
    uint256 fee_
  ) Originator(LM_, strategist_, fee_) {}

  struct MerkleProof {
    bytes32 root;
    bytes32[] proof;
  }

  struct Details {
    address custodian;
    address conduit;
    address issuer;
    uint256 deadline;
    LoanManager.Terms terms;
    SpentItem[] collateral;
    SpentItem[] debt;
    bytes validator;
  }

  function terms(
    bytes calldata details
  ) public view override returns (LoanManager.Terms memory) {
    return abi.decode(details, (Details)).terms;
  }

  function _build(
    Request calldata params,
    Details memory details
  ) internal view returns (Response memory response) {
    bool needsMint = details.issuer.code.length > 0;
    response = Response({terms: details.terms, issuer: details.issuer});
  }

  function _validateMerkleProof(
    MerkleProof memory incomingMerkleProof,
    bytes32 leafHash
  ) internal view virtual {
    if (
      !MerkleProofLib.verify(
        incomingMerkleProof.proof,
        incomingMerkleProof.root,
        leafHash
      )
    ) {
      revert InvalidMerkleProof();
    }
  }

  function execute(
    Request calldata params
  ) external override returns (Response memory response) {
    Details memory details = abi.decode(params.details, (Details));
    MerkleProof memory proof = abi.decode(details.validator, (MerkleProof));

    bytes32 leafHash = keccak256(
      abi.encode(
        details.custodian,
        details.conduit,
        details.issuer,
        details.deadline,
        details.terms,
        details.collateral,
        details.debt
      )
    );

    _validateMerkleProof(proof, leafHash);
    console.logBytes32(proof.root);
    _validateSignature(
      keccak256(encodeWithAccountCounter(strategist, proof.root)),
      params.signature
    );

    if (block.timestamp > details.deadline) {
      revert InvalidDeadline();
    }

    _validateAsk(params, details);
    if (params.debt.length > 1) {
      revert InvalidDebtLength();
    }

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
    Request calldata request,
    Details memory details
  ) internal {
    //        if (request.borrower == address(0)) {
    //          revert InvalidBorrower();
    //        }
    if (request.custodian != details.custodian) {
      revert InvalidCustodian();
    }
    //    if (request.details.length > 0) {
    //      revert InvalidDetails();
    //    }
    //    if (keccak256(request.collateral))
  }

  function getFeeConsideration(
    LoanManager.Loan calldata loan
  ) external view override returns (ReceivedItem[] memory consideration) {
    consideration;
  }
}
