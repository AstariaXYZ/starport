pragma solidity =0.8.17;

import {ERC721} from "solady/src/tokens/ERC721.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import {ERC1155} from "solady/src/tokens/ERC1155.sol";

import {ItemType, OfferItem, Schema, SpentItem, ReceivedItem} from "seaport-types/src/lib/ConsiderationStructs.sol";

import {ContractOffererInterface} from "seaport-types/src/interfaces/ContractOffererInterface.sol";
import {TokenReceiverInterface} from "src/interfaces/TokenReceiverInterface.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {Originator} from "src/originators/Originator.sol";
import {SettlementHook} from "src/hooks/SettlementHook.sol";
import {SettlementHandler} from "src/handlers/SettlementHandler.sol";
import {Pricing} from "src/pricing/Pricing.sol";

import {StarLiteLib} from "src/lib/StarLiteLib.sol";

import "forge-std/console.sol";

import {Custodian} from "src/Custodian.sol";
import {ECDSA} from "solady/src/utils/ECDSA.sol";
import {SignatureCheckerLib} from "solady/src/utils/SignatureCheckerLib.sol";

contract LoanManager is ERC721, ContractOffererInterface {
    using FixedPointMathLib for uint256;
    using {StarLiteLib.toReceivedItems} for SpentItem[];

    address public immutable custodian;
    //  address public feeRecipient;
    address public constant seaport = address(0x2e234DAe75C793f67A35089C9d99245E1C58470b);
    //  uint256 public fee;
    //  uint256 private constant ONE_WORD = 0x20;

    enum FieldFlags {
        INITIALIZED,
        ACTIVE,
        INACTIVE
    }

    struct Terms {
        address hook;
        address pricing;
        address handler;
        bytes pricingData;
        bytes handlerData;
        bytes hookData;
    }

    struct Loan {
        uint256 start;
        address custodian;
        address borrower;
        address issuer;
        address originator;
        SpentItem[] collateral;
        SpentItem[] debt;
        Terms terms;
    }

    struct Obligation {
        bool isTrusted;
        bytes32 hash;
        address originator;
        address custodian;
        address borrower;
        SpentItem[] debt;
        bytes details;
        bytes signature;
    }

    event Close(uint256 loanId);
    event Open(uint256 loanId, LoanManager.Loan loan);
    event SeaportCompatibleContractDeployed();

    error InvalidSender();
    error InvalidAction();
    error InvalidLoan(uint256);
    error InvalidAmount();
    error InvalidDuration();
    error InvalidSignature();
    error InvalidOrigination();
    error InvalidSigner();
    error InvalidContext(ContextErrors);

    enum ContextErrors {
        BAD_ORIGINATION,
        INVALID_PAYMENT,
        LENGTH_MISMATCH,
        BORROWER_MISMATCH,
        COLLATERAL,
        ZERO_ADDRESS,
        INVALID_LOAN,
        INVALID_CONDUIT,
        INVALID_RESOLVER,
        INVALID_COLLATERAL
    }

    constructor() {
        custodian = address(new Custodian(this, seaport));
        emit SeaportCompatibleContractDeployed();
    }

    function name() public pure override returns (string memory) {
        return "Astaria Loan Manager";
    }

    function symbol() public pure override returns (string memory) {
        return "ALM";
    }

    // MODIFIERS
    modifier onlySeaport() {
        if (msg.sender != seaport) {
            revert InvalidSender();
        }
        _;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        return string(abi.encodePacked("https://astaria.xyz/loans?id=", tokenId));
    }

    function _issued(uint256 tokenId) internal view returns (bool) {
        return (_getExtraData(tokenId) > uint8(0));
    }

    function getIssuer(Loan calldata loan) external view returns (address payable) {
        uint256 loanId = uint256(keccak256(abi.encode(loan)));
        if (!_issued(loanId)) {
            revert InvalidLoan(loanId);
        }
        return !_exists(loanId) ? payable(loan.issuer) : payable(ownerOf(loanId));
    }

    //break the revert of the ownerOf method, so we can ensure anyone calling it in the settlement pipeline wont halt
    function ownerOf(uint256 loanId) public view override returns (address) {
        //not hasn't been issued but exists if we own it
        return _issued(loanId) && !_exists(loanId) ? address(this) : _ownerOf(loanId);
    }

    function settle(Loan calldata loan) external {
        if (msg.sender != loan.custodian) {
            revert InvalidSender();
        }
        uint256 tokenId = uint256(keccak256(abi.encode(loan)));
        if (!_issued(tokenId)) {
            revert InvalidLoan(tokenId);
        }
        if (_exists(tokenId)) {
            _burn(tokenId);
        }
        emit Close(tokenId);
    }

    /**
     * @dev previews the order for this contract offerer.
     *
     * @param caller        The address of the contract fulfiller.
     * @param fulfiller        The address of the contract fulfiller.
     * @param minimumReceived  The minimum the fulfiller must receive.
     * @param maximumSpent     The most a fulfiller will spend
     * @param context          The context of the order.
     * @return offer     The items spent by the order.
     * @return consideration  The items received by the order.
     */
    function previewOrder(
        address caller,
        address fulfiller,
        SpentItem[] calldata minimumReceived,
        SpentItem[] calldata maximumSpent,
        bytes calldata context // encoded based on the schemaID
    ) public view returns (SpentItem[] memory offer, ReceivedItem[] memory consideration) {
        LoanManager.Obligation memory obligation = abi.decode(context, (LoanManager.Obligation));
        consideration = maximumSpent.toReceivedItems(obligation.custodian);
    }

    /**
     * @dev Gets the metadata for this contract offerer.
     *
     * @return name    The name of the contract offerer.
     * @return schemas The schemas supported by the contract offerer.
     */
    function getSeaportMetadata() external pure returns (string memory, Schema[] memory schemas) {
        schemas = new Schema[](1);
        schemas[0] = Schema(8, "");
        return ("Loans", schemas);
    }

    function _fillObligationAndVerify(
        address fulfiller,
        LoanManager.Obligation memory obligation,
        SpentItem[] calldata maximumSpentFromBorrower
    ) internal returns (SpentItem[] memory offer) {
        address receiver = obligation.borrower;
        bool isTrustedExecution = fulfiller == receiver && obligation.isTrusted;
        receiver = isTrustedExecution ? obligation.borrower : address(this);

        //make template
        // struct Request {
        //    address custodian;
        //    address borrower;
        //    SpentItem[] collateral;
        //    bytes details;
        //    bytes signature;
        //  }
        Originator.Response memory response = Originator(obligation.originator).execute(
            Originator.Request({
                custodian: obligation.custodian,
                receiver: receiver,
                collateral: maximumSpentFromBorrower,
                debt: obligation.debt,
                details: obligation.details,
                signature: obligation.signature
            })
        );
        Loan memory loan = Loan({
            start: uint256(0),
            issuer: address(0),
            custodian: obligation.custodian,
            borrower: obligation.borrower,
            originator: !isTrustedExecution ? address(0) : obligation.originator,
            collateral: maximumSpentFromBorrower,
            debt: obligation.debt,
            terms: response.terms
        });
        // we settle via seaport channels if a match is happening
        if (!isTrustedExecution) {
            bytes32 loanHash = keccak256(abi.encode(loan));
            if (loanHash != obligation.hash) {
                revert InvalidOrigination();
            }

            offer = _setOffer(loan.debt, loanHash);
            _setDebtApprovals(loan.debt);
        }

        loan.start = block.timestamp;
        loan.originator = obligation.originator;
        loan.issuer = response.issuer;
        _issueLoanManager(loan, response.mint);
    }

    function _issueLoanManager(Loan memory loan, bool mint) internal {
        bytes memory encodedLoan = abi.encode(loan);

        uint256 loanId = uint256(keccak256(encodedLoan));

        _setExtraData(loanId, uint8(FieldFlags.ACTIVE));
        if (mint) {
            _safeMint(loan.issuer, loanId, encodedLoan);
        }
        emit Open(loanId, loan);
    }

    function issue(Loan calldata loan) external {
        bytes memory encodedLoan = abi.encode(loan);
        uint256 loanId = uint256(keccak256(encodedLoan));
        if (_getExtraData(loanId) == uint8(FieldFlags.INITIALIZED)) {
            revert InvalidLoan(loanId);
        }
        _safeMint(loan.issuer, loanId, encodedLoan);
    }

    /**
     * @dev Generates the order for this contract offerer.
     *
     * @param fulfiller        The address of the contract fulfiller.
     * @param maximumSpent     The maximum amount of items to be spent by the order.
     * @param context          The context of the order.
     * @return offer           The items spent by the order.
     * @return consideration   The items received by the order.
     */
    function generateOrder(
        address fulfiller,
        SpentItem[] calldata minimumReceived,
        SpentItem[] calldata maximumSpent,
        bytes calldata context // encoded based on the schemaID
    ) external onlySeaport returns (SpentItem[] memory offer, ReceivedItem[] memory consideration) {
        LoanManager.Obligation memory obligation = abi.decode(context, (LoanManager.Obligation));
        consideration = maximumSpent.toReceivedItems(obligation.custodian);

        offer = _fillObligationAndVerify(fulfiller, obligation, maximumSpent);
    }

    function _setDebtApprovals(SpentItem[] memory debt) internal {
        uint256 i = 0;
        for (; i < debt.length;) {
            //approve consideration based on item type
            if (debt[i].itemType != ItemType.ERC20) {
                ERC721(debt[i].token).setApprovalForAll(seaport, true);
            } else {
                ERC20(debt[i].token).approve(seaport, debt[i].amount);
            }
            unchecked {
                ++i;
            }
        }
    }

    function _setOffer(SpentItem[] memory debt, bytes32 loanHash) internal returns (SpentItem[] memory offer) {
        offer = new SpentItem[](debt.length + 1);
        offer[0] =
            SpentItem({itemType: ItemType.ERC721, token: address(this), identifier: uint256(loanHash), amount: 1});
        uint256 i = 0;

        for (; i < debt.length;) {
            offer[i + 1] = debt[i];
            unchecked {
                ++i;
            }
        }
    }

    function transferFrom(address from, address to, uint256 tokenId) public payable override {
        if (from != address(this)) super.transferFrom(from, to, tokenId);
    }

    /**
     * @dev Generates the order for this contract offerer.
     *
     * @param offer            The address of the contract fulfiller.
     * @param consideration    The maximum amount of items to be spent by the order.
     * @param context          The context of the order.
     * @param orderHashes      The context of the order.
     * @param contractNonce    The context of the order.
     * @return ratifyOrderMagicValue The magic value returned by the ratify.
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

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721, ContractOffererInterface)
        returns (bool)
    {
        return interfaceId == type(ContractOffererInterface).interfaceId || interfaceId == type(ERC721).interfaceId
            || super.supportsInterface(interfaceId);
    }
}
