pragma solidity =0.8.17;

import {ERC721} from "solmate/tokens/ERC721.sol";

import {ConduitTransfer, ConduitItemType} from "seaport-types/src/conduit/lib/ConduitStructs.sol";
import {ItemType, OfferItem, Schema, SpentItem, ReceivedItem, OrderParameters} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {ConduitControllerInterface} from "seaport-types/src/interfaces/ConduitControllerInterface.sol";
import {ConsiderationInterface} from "seaport-types/src/interfaces/ConsiderationInterface.sol";
import {ConduitInterface} from "seaport-types/src/interfaces/ConduitInterface.sol";
import {ContractOffererInterface} from "seaport-types/src/interfaces/ContractOffererInterface.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {AmountDeriver} from "seaport-core/src/lib/AmountDeriver.sol";

/**
 * @title ERC721 token receiver interface
 * @dev Interface for any contract that wants to support safeTransfers
 * from ERC721 asset contracts.
 */
interface IERC721Receiver {
    /**
     * @dev Whenever an {IERC721} `tokenId` token is transferred to this contract via {IERC721-safeTransferFrom}
   * by `operator` from `from`, this function is called.
   *
   * It must return its Solidity selector to confirm the token transfer.
   * If any other value is returned or the interface is not implemented by the recipient, the transfer will be reverted.
   *
   * The selector can be obtained in Solidity with `IERC721Receiver.onERC721Received.selector`.
   */
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}


interface Validator {
    struct Loan {
        ItemType itemType;
        address borrower;
        address validator;
        address token;
        address debtToken;
        uint256 identifier;
        uint256 identifierAmount;
        uint256 amount;
        uint256 rate;
        uint256 start;
        uint256 duration;
        uint256 nonce;
        bytes extraData;
    }

    function execute(LoanManager.NewLoanRequest calldata nlr, ReceivedItem calldata consideration) external returns (Loan memory, address lender);

    function getOwed(Loan calldata loan, uint256 timestamp) external pure returns (uint256);

    function getSettlementData(Loan calldata loan) external view returns (uint256, uint256);

}

contract LoanManager is ERC721("LoanManager", "LM"), AmountDeriver, ContractOffererInterface, IERC721Receiver {
    using FixedPointMathLib for uint256;
    uint256 private constant OUTOFBOUND_ERROR_SELECTOR = 0x571e08d100000000000000000000000000000000000000000000000000000000;
    uint256 private constant ONE_WORD = 0x20;

    enum Action {
        OPEN,
        CLOSE
    }
    struct BorrowerDetails {
        address who;
        address what;
        uint256 howMuch;
    }

    struct NewLoanRequest {
        address lender;
        BorrowerDetails borrowerDetails;
        uint8 v;
        bytes32 r;
        bytes32 s;
        bytes details;
    }

    event LoanOpened(uint256 indexed loanId, Validator.Loan loan);
    event LoanClosed(uint256 indexed loanId, uint256 amount, bool liquidated);
    event SeaportCompatibleContractDeployed();

    error InvalidSender();
    error InvalidAction();
    error InvalidLoan(uint256);
    error InvalidAmount();
    error InvalidContext();
    error LoanHealthy();
    error StateMismatch(uint256);
    error UnsupportedExtraDataVersion(uint8 version);
    error InvalidExtraDataEncoding(uint8 version);

    address public seaport;

    uint256 public loanCount;
    constructor(address consideration) {
        seaport = consideration;
        loanCount = 1;
        emit SeaportCompatibleContractDeployed();
    }

    // MODIFIERS
    modifier onlySeaport {
        if (msg.sender != seaport) {
            revert InvalidSender();
        }
        _;
    }

    // PUBLIC FUNCTIONS
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) public virtual returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function tokenURI(uint256 tokenId) public override view returns (string memory) {
        return string(abi.encodePacked("https://astaria.xyz/loans?id=", tokenId));
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

        uint8 action = abi.decode(context[: 32], (uint8));

        if (action == uint8(Action.OPEN)) {
            consideration = new ReceivedItem[](maximumSpent.length);
            for (uint256 i = 0; i < maximumSpent.length; i++) {
                consideration[i] = ReceivedItem({
                itemType : maximumSpent[i].itemType,
                token : maximumSpent[i].token,
                identifier : maximumSpent[i].identifier,
                amount : maximumSpent[i].amount,
                recipient : payable(address(this))
                });
            }
        } else if (action == uint8(Action.CLOSE)) {
            (,Validator.Loan memory loan) = abi.decode(context, (uint8, Validator.Loan));
            (uint256 owed, uint256 settlementPrice) = Validator(loan.validator).getSettlementData(loan);

            if (loan.start + loan.duration < block.timestamp) {
                if (maximumSpent[0].amount < owed) {
                    revert InvalidAmount();
                }
                consideration = new ReceivedItem[](1);
                consideration[0] = ReceivedItem({
                itemType : ItemType.ERC20,
                token : loan.debtToken,
                identifier : 0,
                amount : owed,
                recipient : payable(ownerOf(uint256(keccak256(abi.encode(loan)))))
                });
            } else {
                //now were in liquidation
                offer = new SpentItem[](1);
                offer[0] = SpentItem({
                itemType : loan.itemType,
                token : loan.token,
                identifier : loan.identifier,
                amount : loan.identifierAmount
                });

                (uint256 startPrice, uint256 endPrice, uint256 auctionDuration) = abi.decode(loan.extraData, (uint256, uint256, uint256));
                consideration = new ReceivedItem[](2);

                if (maximumSpent[0].amount < settlementPrice) {
                    revert InvalidAmount();
                }
                consideration[0] = ReceivedItem({
                itemType : ItemType.ERC20,
                token : loan.debtToken,
                identifier : 0,
                amount : settlementPrice,
                recipient : payable(ownerOf(uint256(keccak256(abi.encode(loan)))))
                });
                consideration[1] = ReceivedItem({
                itemType : ItemType.ERC20,
                token : loan.token,
                identifier : loan.identifier,
                amount : maximumSpent[0].amount - settlementPrice,
                recipient : payable(loan.borrower)
                });
            }
        } else {
            revert InvalidAction();
        }
    }

    /**
     * @dev Gets the metadata for this contract offerer.
     *
     * @return name    The name of the contract offerer.
     * @return schemas The schemas supported by the contract offerer.
     */
    function getSeaportMetadata() external view returns (string memory name, Schema[] memory schemas) {
        schemas = new Schema[](1);
        uint schemaId = uint(8);
        schemas[0] = Schema(8, "");
        return ("Loans", schemas);
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
    ) onlySeaport external returns (SpentItem[] memory offer, ReceivedItem[] memory consideration) {
        return previewOrder(msg.sender, fulfiller, minimumReceived, maximumSpent, context);
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
    ) onlySeaport external returns (bytes4 ratifyOrderMagicValue) {
        //get the spent token and amount from the spent item

        uint8 action = abi.decode(context[: 32], (uint8));

        if (action == uint8(Action.OPEN)) {
            _executeLoanOpen(consideration, context);
        } else if (action == uint8(Action.CLOSE)) {
            _executeLoanClosed(consideration, context);
        } else {
            revert InvalidAction();
        }

        return ContractOffererInterface.ratifyOrder.selector;
    }

    //do more work here
    function forgive(Validator.Loan calldata loan) public {
        uint256 loanId = uint256(keccak256(abi.encode(loan)));
        if (msg.sender != ownerOf(loanId)) {
            revert InvalidSender();
        }

        _burn(loanId);

        ERC721(loan.token).transferFrom(address(this), msg.sender, loan.identifier);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, ContractOffererInterface) returns (bool) {
        return interfaceId == type(ContractOffererInterface).interfaceId || interfaceId == type(ERC721).interfaceId || super.supportsInterface(interfaceId);
    }

    // INTERNAL FUNCTIONS

    function _executeLoanOpen(ReceivedItem[] calldata consideration, bytes calldata context) internal {

        (, LoanManager.NewLoanRequest[] memory nlrs) = abi.decode(context, (uint8, LoanManager.NewLoanRequest[]));

        if (nlrs.length != consideration.length) {
            revert InvalidContext();
        }
        uint i = 0;
        for (; i < nlrs.length; ) {
            address validator;
            bytes memory data = nlrs[i].details;
            assembly {
                validator := mload(add(data, 64))
            }
            if (validator == address(0)) {
                revert InvalidContext();
            }
            (Validator.Loan memory loan, address lender) = Validator(validator).execute(nlrs[i], consideration[i]);
            loan.nonce = ++loanCount;
            uint256 loanId = uint256(keccak256(abi.encode(loan)));
            _safeMint(lender, loanId);
            emit LoanOpened(loanId, loan);
            unchecked {
                ++i;
            }
        }
    }

    function _executeLoanClosed(ReceivedItem[] calldata consideration, bytes calldata context) internal {
        Validator.Loan memory loan = abi.decode(context[32 :], (Validator.Loan));

        uint256 loanId = uint256(keccak256(abi.encode(loan)));

        bool liquidated = true;
        if (loan.start + loan.duration > block.timestamp) {
            ERC721(loan.token).safeTransferFrom(address(this), loan.borrower, loan.identifier, "");
            liquidated = false;
        }
        emit LoanClosed(loanId, consideration[0].amount, liquidated);
        _burn(loanId);
    }
}

contract UniqueValidator is Validator, AmountDeriver {

    error InvalidDeadline();
    error InvalidValidator();
    error InvalidCollateral();
    error InvalidBorrowAmount();
    error InvalidAmount();

    error LoanHealthy();

    struct Details {
        address validator;
        uint256 deadline;
        address conduit;
        address token;
        uint256 tokenId;
        uint256 maxAmount;
        uint256 rate; //rate per second
        uint256 duration;
        bytes extraData;
    }

    LoanManager public immutable LM;
    constructor(LoanManager LM_) {
        LM = LM_;
    }

    function execute(LoanManager.NewLoanRequest calldata nlr, ReceivedItem calldata consideration) external override returns (Loan memory, address lender) {

        Details memory details = abi.decode(nlr.details, (Details));

        if (address(this) != details.validator) {
            revert InvalidValidator();
        }
        if (block.timestamp > details.deadline) {
            revert InvalidDeadline();
        }
        if (details.token != consideration.token || details.tokenId != consideration.identifier) {
            revert InvalidCollateral();
        }

        if (nlr.borrowerDetails.howMuch > details.maxAmount || nlr.borrowerDetails.howMuch == 0) {
            revert InvalidBorrowAmount();
        }

        lender = ecrecover(keccak256(nlr.details), nlr.v, nlr.r, nlr.s);


        ConduitTransfer[] memory transfers = new ConduitTransfer[](1);
        transfers[0] = ConduitTransfer(
            ConduitItemType.ERC20,
            nlr.borrowerDetails.what,
            lender,
            nlr.borrowerDetails.who,
            0,
            nlr.borrowerDetails.howMuch
        );
        ConduitInterface(details.conduit).execute(transfers);
        return (
        Loan({
        itemType : consideration.itemType,
        borrower : nlr.borrowerDetails.who,
        validator : address(this),
        token : consideration.token,
        identifier : consideration.identifier,
        identifierAmount : consideration.amount,
        debtToken : nlr.borrowerDetails.what,
        amount : nlr.borrowerDetails.howMuch,
        rate : details.rate,
        start : block.timestamp,
        duration : details.duration,
        nonce : uint256(0),
        extraData : details.extraData
        }), lender
        );
    }

    function getOwed(Loan calldata loan, uint256 timestamp) public pure override returns (uint256) {
        return loan.amount * loan.rate * (loan.start + loan.duration - timestamp);
    }

    function getSettlementData(Loan calldata loan) public view override returns (uint256, uint256) {
        (uint256 startPrice, uint256 endPrice, uint256 auctionDuration) = abi.decode(loan.extraData, (uint256, uint256, uint256));
        return (getOwed(loan, block.timestamp), _locateCurrentAmount({
        startAmount : startPrice,
        endAmount : endPrice,
        startTime : loan.start + loan.duration,
        endTime : block.timestamp + auctionDuration,
        roundUp : true
        }));
    }
}