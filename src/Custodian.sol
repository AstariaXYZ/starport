// SPDX-License-Identifier: BUSL-1.1
//
//                       ↑↑↑↑                 ↑↑
//                       ↑↑↑↑                ↑↑↑↑↑
//                       ↑↑↑↑              ↑   ↑
//                       ↑↑↑↑            ↑↑↑↑↑
//            ↑          ↑↑↑↑          ↑   ↑
//          ↑↑↑↑↑        ↑↑↑↑        ↑↑↑↑↑
//            ↑↑↑↑↑      ↑↑↑↑      ↑↑↑↑↑                                   ↑↑↑                                                                      ↑↑↑
//              ↑↑↑↑↑    ↑↑↑↑    ↑↑↑↑↑                          ↑↑↑        ↑↑↑         ↑↑↑            ↑↑         ↑↑            ↑↑↑            ↑↑    ↑↑↑
//                ↑↑↑↑↑  ↑↑↑↑  ↑↑↑↑↑                         ↑↑↑↑ ↑↑↑↑   ↑↑↑↑↑↑↑    ↑↑↑↑↑↑↑↑↑     ↑↑ ↑↑↑   ↑↑↑↑↑↑↑↑↑↑↑     ↑↑↑↑↑↑↑↑↑↑    ↑↑↑ ↑↑↑  ↑↑↑↑↑↑↑
//                  ↑↑↑↑↑↑↑↑↑↑↑↑↑↑                           ↑↑     ↑↑↑    ↑↑↑     ↑↑↑     ↑↑↑    ↑↑↑      ↑↑↑      ↑↑↑   ↑↑↑      ↑↑↑   ↑↑↑↑       ↑↑↑
//                    ↑↑↑↑↑↑↑↑↑↑                             ↑↑↑↑↑         ↑↑↑            ↑↑↑↑    ↑↑       ↑↑↑       ↑↑   ↑↑↑       ↑↑↑  ↑↑↑        ↑↑↑
//  ↑↑↑↑  ↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑   ↑↑↑   ↑↑↑             ↑↑↑↑↑↑↑    ↑↑↑     ↑↑↑↑↑↑  ↑↑↑    ↑↑       ↑↑↑       ↑↑↑  ↑↑↑       ↑↑↑  ↑↑↑        ↑↑↑
//  ↑↑↑↑  ↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑   ↑↑↑   ↑↑↑                  ↑↑    ↑↑↑     ↑↑      ↑↑↑    ↑↑       ↑↑↑      ↑↑↑   ↑↑↑      ↑↑↑   ↑↑↑        ↑↑↑
//                    ↑↑↑↑↑↑↑↑↑↑                             ↑↑↑    ↑↑↑    ↑↑↑     ↑↑↑    ↑↑↑↑    ↑↑       ↑↑↑↑↑  ↑↑↑↑     ↑↑↑↑   ↑↑↑    ↑↑↑        ↑↑↑
//                  ↑↑↑↑↑↑↑↑↑↑↑↑↑↑                             ↑↑↑↑↑↑       ↑↑↑↑     ↑↑↑↑↑ ↑↑↑    ↑↑       ↑↑↑ ↑↑↑↑↑↑        ↑↑↑↑↑↑      ↑↑↑          ↑↑↑
//                ↑↑↑↑↑  ↑↑↑↑  ↑↑↑↑↑                                                                       ↑↑↑
//              ↑↑↑↑↑    ↑↑↑↑    ↑↑↑↑                                                                      ↑↑↑     Starport: Lending Kernel
//                ↑      ↑↑↑↑     ↑↑↑↑↑
//                       ↑↑↑↑       ↑↑↑↑↑                                                                          Designed with love by Astaria Labs, Inc
//                       ↑↑↑↑         ↑
//                       ↑↑↑↑
//                       ↑↑↑↑
//                       ↑↑↑↑
//                       ↑↑↑↑

pragma solidity ^0.8.17;

import {Starport} from "./Starport.sol";
import {Pricing} from "./pricing/Pricing.sol";
import {Settlement} from "./settlement/Settlement.sol";
import {Status} from "./status/Status.sol";
import {StarportLib, Actions} from "./lib/StarportLib.sol";

import {ContractOffererInterface} from "seaport-types/src/interfaces/ContractOffererInterface.sol";
import {ItemType, Schema, SpentItem, ReceivedItem} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {ERC721} from "solady/src/tokens/ERC721.sol";
import {ERC1155} from "solady/src/tokens/ERC1155.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {LibString} from "solady/src/utils/LibString.sol";

contract Custodian is ERC721, ContractOffererInterface {
    using {StarportLib.getId} for Starport.Loan;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    error CustodianCannotBeAuthorized();
    error ImplementInChild();
    error InvalidAction();
    error InvalidFulfiller();
    error InvalidLoan();
    error InvalidPostRepayment();
    error InvalidPostSettlement();
    error InvalidRepayer();
    error NotAuthorized();
    error NotEnteredViaSeaport();
    error NotSeaport();
    error NotStarport();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event SeaportCompatibleContractDeployed();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  CONSTANTS AND IMMUTABLES                  */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    Starport public immutable SP;
    address public immutable seaport;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STRUCTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    struct Command {
        Actions action;
        Starport.Loan loan;
        bytes extraData;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CONSTRUCTOR                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    constructor(Starport SP_, address seaport_) {
        seaport = seaport_;
        SP = SP_;

        emit SeaportCompatibleContractDeployed();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     FUNCTION OVERRIDES                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @dev The name of the ERC721 contract
     * @return string The name of the contract
     */
    function name() public pure override returns (string memory) {
        return "Starport Custodian";
    }

    /**
     * @dev The symbol of the ERC721 contract
     * @return string The symbol of the contract
     */
    function symbol() public pure override returns (string memory) {
        return "SC";
    }

    /**
     * @dev ERC-721 tokenURI override
     * @param loanId The id of the custody token/loan
     * @return string URI of the custody token/loan
     */
    function tokenURI(uint256 loanId) public view override returns (string memory) {
        if (!_exists(loanId)) {
            revert InvalidLoan();
        }
        return string(abi.encodePacked("https://astaria.xyz/loans/", LibString.toString(loanId)));
    }

    /**
     * @dev Helper to determine if an interface is supported by this contract
     * @param interfaceId The interface to check
     * @return bool Returns true if the interface is supported
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override (ERC721, ContractOffererInterface)
        returns (bool)
    {
        return interfaceId == type(ERC721).interfaceId || interfaceId == type(ContractOffererInterface).interfaceId
            || super.supportsInterface(interfaceId);
    }

    /**
     * @dev onERC1155Received handler, if we are able to increment the counter
     * in seaport that means we have not entered into seaport we dont add for
     * ERC-721 as they are able to ignore the on handler call as apart of the spec
     * revert with NotEnteredViaSeaport()
     */
    function onERC1155Received(address, address, uint256, uint256, bytes calldata) public virtual returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      EXTERNAL FUNCTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @dev Mints a custody token for a loan.
     * @param loan The loan to mint a custody token for
     */
    function mint(Starport.Loan calldata loan) external {
        _validateAndMint(loan);
    }

    /**
     * @dev Mints a custody token for a loan.
     * @param loan The loan to mint a custody token for
     * @param approvedTo The address with pre approvals set
     */
    function mintWithApprovalSet(Starport.Loan calldata loan, address approvedTo) external {
        if (msg.sender != loan.borrower) {
            revert NotAuthorized();
        }
        _approve(loan.borrower, approvedTo, _validateAndMint(loan));
    }

    /**
     * @dev internal helper that validates and mints a custody token for a loan.
     * @param loan The loan to mint a custody token for
     */
    function _validateAndMint(Starport.Loan calldata loan) internal returns (uint256 loanId) {
        loanId = loan.getId();
        if (loan.custodian != address(this) || SP.closed(loanId)) {
            revert InvalidLoan();
        }
        _safeMint(loan.borrower, loanId);
    }

    /**
     * @dev Generates the order for this contract offerer
     * @param offer The address of the contract fulfiller
     * @param consideration The maximum amount of items to be spent by the order
     * @param context The context of the order
     * @param orderHashes The context of the order
     * @param contractNonce The context of the order
     * @return ratifyOrderMagicValue The magic value returned by the ratify
     */
    function ratifyOrder(
        SpentItem[] calldata offer,
        ReceivedItem[] calldata consideration,
        bytes calldata context, // encoded based on the schemaID
        bytes32[] calldata orderHashes,
        uint256 contractNonce
    ) external onlySeaport returns (bytes4 ratifyOrderMagicValue) {
        ratifyOrderMagicValue = ContractOffererInterface.ratifyOrder.selector;
    }

    /**
     * @dev Generates the order for this contract offerer
     * @param fulfiller The address of the contract fulfiller
     * @param maximumSpent The maximum amount of items to be spent by the order
     * @param context The context of the order
     * @return offer The items spent by the order
     * @return consideration The items received by the order
     */
    function generateOrder(
        address fulfiller,
        SpentItem[] calldata,
        SpentItem[] calldata maximumSpent,
        bytes calldata context // encoded based on the schemaID
    ) external onlySeaport returns (SpentItem[] memory offer, ReceivedItem[] memory consideration) {
        (Command memory close) = abi.decode(context, (Command));
        Starport.Loan memory loan = close.loan;
        if (loan.start == block.timestamp) {
            revert InvalidLoan();
        }
        if (close.action == Actions.Repayment && Status(loan.terms.status).isActive(loan, close.extraData)) {
            if (fulfiller != getBorrower(loan) && fulfiller != _getApproved(loan.getId())) {
                revert InvalidRepayer();
            }

            offer = loan.collateral;
            _setOfferApprovalsWithSeaport(loan);
            (SpentItem[] memory payment, SpentItem[] memory carry) =
                Pricing(loan.terms.pricing).getPaymentConsideration(loan);

            consideration = StarportLib.mergeSpentItemsToReceivedItems(payment, loan.issuer, carry, loan.originator);

            _settleLoan(loan);
            _postRepaymentExecute(loan, fulfiller);
        } else if (close.action == Actions.Settlement && !Status(loan.terms.status).isActive(loan, close.extraData)) {
            address authorized;
            _beforeGetSettlementConsideration(loan);
            (consideration, authorized) = Settlement(loan.terms.settlement).getSettlementConsideration(loan);
            if (authorized == address(this)) {
                revert CustodianCannotBeAuthorized();
            }
            consideration = StarportLib.removeZeroAmountItems(consideration);
            _afterGetSettlementConsideration(loan);
            if (authorized == address(0) || fulfiller == authorized) {
                offer = loan.collateral;
                _setOfferApprovalsWithSeaport(loan);
            } else if (authorized == loan.terms.settlement || authorized == loan.issuer) {
                _moveCollateralToAuthorized(loan.collateral, authorized);
            } else {
                revert InvalidFulfiller();
            }
            _settleLoan(loan);
            _postSettlementExecute(loan, fulfiller);
        } else {
            revert InvalidAction();
        }
    }

    /**
     * @dev If any additional state updates are needed when taking custody of a loan
     * @param loan The loan that was just placed into custody
     * @return selector The function selector of the custody method
     */
    function custody(Starport.Loan memory loan) external virtual onlyStarport returns (bytes4 selector) {
        revert ImplementInChild();
    }

    /**
     * @dev Returns metadata on how to interact with the offerer contract
     * @return string The name of the contract
     * @return schemas An array of supported schemas
     */
    function getSeaportMetadata() external pure returns (string memory, Schema[] memory schemas) {
        // Adhere to SIP data, how to encode the context and what it is
        // TODO: add in the context for the loan
        // you need to parse SP Open events for the loan and ABI encode it
        schemas = new Schema[](1);
        schemas[0] = Schema(8, "");
        return ("Loans", schemas);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     PUBLIC FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @dev Fetches the borrower of the loan, first checks to see if we've minted the token for the loan
     * @param loan Loan to get the borrower of
     * @return address The address of the loan borrower(returns the ownerOf the token if any) defaults to loan.borrower
     */
    function getBorrower(Starport.Loan memory loan) public view returns (address) {
        uint256 loanId = loan.getId();
        return _exists(loanId) ? ownerOf(loanId) : loan.borrower;
    }

    /**
     * @dev Previews the order for this contract offerer.
     * @param caller The address of the contract fulfiller.
     * @param fulfiller The address of the contract fulfiller.
     * @param minimumReceived The minimum the fulfiller must receive.
     * @param maximumSpent The most a fulfiller will spend
     * @param context The context of the order.
     * @return offer The items spent by the order.
     * @return consideration The items received by the order.
     */
    function previewOrder(
        address caller,
        address fulfiller,
        SpentItem[] calldata minimumReceived,
        SpentItem[] calldata maximumSpent,
        bytes calldata context // Encoded based on the schemaID
    ) public view returns (SpentItem[] memory offer, ReceivedItem[] memory consideration) {
        (Command memory close) = abi.decode(context, (Command));
        Starport.Loan memory loan = close.loan;
        if (loan.start == block.timestamp || SP.closed(loan.getId())) {
            revert InvalidLoan();
        }
        bool loanActive = Status(loan.terms.status).isActive(loan, close.extraData);
        if (close.action == Actions.Repayment && loanActive) {
            address borrower = getBorrower(loan);
            if (fulfiller != borrower && fulfiller != _getApproved(loan.getId())) {
                revert InvalidRepayer();
            }
            offer = loan.collateral;

            (SpentItem[] memory payment, SpentItem[] memory carry) =
                Pricing(loan.terms.pricing).getPaymentConsideration(loan);
            consideration = StarportLib.mergeSpentItemsToReceivedItems(payment, loan.issuer, carry, loan.originator);
        } else if (close.action == Actions.Settlement && !loanActive) {
            address authorized;
            (consideration, authorized) = Settlement(loan.terms.settlement).getSettlementConsideration(loan);
            if (authorized == address(this)) {
                revert CustodianCannotBeAuthorized();
            }
            consideration = StarportLib.removeZeroAmountItems(consideration);
            if (authorized == address(0) || fulfiller == authorized) {
                offer = loan.collateral;
            } else if (authorized == loan.terms.settlement || authorized == loan.issuer) {} else {
                revert InvalidFulfiller();
            }
        } else {
            revert InvalidAction();
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    INTERNAL FUNCTIONS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @dev Enables the collateral deposited to be spent via seaport
     * @param offer The item to make available to seaport
     */
    function _enableAssetWithSeaport(SpentItem memory offer) internal {
        //approve consideration based on item type
        if (offer.itemType == ItemType.ERC721) {
            ERC721(offer.token).approve(seaport, offer.identifier);
        } else if (offer.itemType == ItemType.ERC1155) {
            ERC1155(offer.token).setApprovalForAll(seaport, true);
        } else if (offer.itemType == ItemType.ERC20) {
            SafeTransferLib.safeApproveWithRetry(offer.token, seaport, type(uint256).max);
        }
    }

    /**
     * @dev Sets approvals for the collateral deposited to be spent via seaport
     * @param loan The loan being settled
     */
    function _setOfferApprovalsWithSeaport(Starport.Loan memory loan) internal {
        _beforeApprovalsSetHook(loan);
        for (uint256 i = 0; i < loan.collateral.length; i++) {
            _enableAssetWithSeaport(loan.collateral[i]);
        }
    }

    /**
     * @dev transfers out the collateral to the handler address
     * @param offer The item to send out of the Custodian
     * @param authorized The address handling the asset further
     */
    function _transferCollateralAuthorized(SpentItem memory offer, address authorized) internal {
        // Approve consideration based on item type
        if (offer.itemType == ItemType.ERC721) {
            ERC721(offer.token).transferFrom(address(this), authorized, offer.identifier);
        } else if (offer.itemType == ItemType.ERC1155) {
            ERC1155(offer.token).safeTransferFrom(address(this), authorized, offer.identifier, offer.amount, "");
        } else if (offer.itemType == ItemType.ERC20) {
            SafeTransferLib.safeTransfer(offer.token, authorized, offer.amount);
        }
    }

    /**
     * @dev transfers out the collateral of SpentItem to the handler address
     * @param offer The SpentItem array to send out of the Custodian
     * @param authorized The address handling the asset further
     */
    function _moveCollateralToAuthorized(SpentItem[] memory offer, address authorized) internal {
        for (uint256 i = 0; i < offer.length; i++) {
            _transferCollateralAuthorized(offer[i], authorized);
        }
    }

    /**
     * @dev settle the loan with Starport
     * @param loan The the loan that is settled
     * @param fulfiller The address executing seaport
     */
    function _postSettlementExecute(Starport.Loan memory loan, address fulfiller) internal virtual {
        _beforeSettlementHandlerHook(loan);
        if (Settlement(loan.terms.settlement).postSettlement(loan, fulfiller) != Settlement.postSettlement.selector) {
            revert InvalidPostSettlement();
        }
        _afterSettlementHandlerHook(loan);
    }

    /**
     * @dev settle the loan with Starport
     * @param loan The the loan that is settled
     * @param fulfiller The address executing seaport
     */
    function _postRepaymentExecute(Starport.Loan memory loan, address fulfiller) internal virtual {
        _beforeSettlementHandlerHook(loan);
        if (Settlement(loan.terms.settlement).postRepayment(loan, fulfiller) != Settlement.postRepayment.selector) {
            revert InvalidPostRepayment();
        }
        _afterSettlementHandlerHook(loan);
    }

    /**
     * @dev settle the loan with Starport
     * @param loan The the loan to settle
     */
    function _settleLoan(Starport.Loan memory loan) internal virtual {
        _beforeSettleLoanHook(loan);
        uint256 loanId = loan.getId();
        if (_exists(loanId)) {
            _burn(loanId);
        }
        SP.settle(loan);
        _afterSettleLoanHook(loan);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                            HOOKS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @dev hook to call before the approvals are set
     * @param loan The loan being settled
     */
    function _beforeApprovalsSetHook(Starport.Loan memory loan) internal virtual {}

    /**
     * @dev  Hook to call before the loan get settlement call
     * @param loan The loan being settled
     */
    function _beforeGetSettlementConsideration(Starport.Loan memory loan) internal virtual {}

    /**
     * @dev  Hook to call after the loan get settlement call
     * @param loan The loan being settled
     */
    function _afterGetSettlementConsideration(Starport.Loan memory loan) internal virtual {}
    /**
     * @dev  Hook to call before the the loan settlement handler execute call
     * @param loan The loan being settled
     */
    function _beforeSettlementHandlerHook(Starport.Loan memory loan) internal virtual {}

    /**
     * @dev  Hook to call after the the loan settlement handler execute call
     * @param loan The loan being settled
     */
    function _afterSettlementHandlerHook(Starport.Loan memory loan) internal virtual {}

    /**
     * @dev  Hook to call before the loan is settled with the Starport
     * @param loan The loan being settled
     */
    function _beforeSettleLoanHook(Starport.Loan memory loan) internal virtual {}

    /**
     * @dev  Hook to call after the loan is settled with the Starport
     * @param loan The loan being settled
     */
    function _afterSettleLoanHook(Starport.Loan memory loan) internal virtual {}

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          MODIFIERS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @dev only allows Starport to execute the function
     */
    modifier onlyStarport() {
        if (msg.sender != address(SP)) {
            revert NotStarport();
        }
        _;
    }

    /**
     * @dev only allows seaport to execute the function
     */
    modifier onlySeaport() {
        if (msg.sender != address(seaport)) {
            revert NotSeaport();
        }
        _;
    }
}
