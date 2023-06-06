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
        address borrower;
        address validator;
        address token;
        uint256 identifier;
        address debtToken;
        uint256 amount;
        uint256 rate;
        uint256 start;
        uint256 duration;
    }

    function execute(LoanManager.NewLoanRequest calldata nlr, address token, uint256 identifier) external returns (Loan memory, address lender);

    function getOwed(Loan calldata loan) external view returns (uint256);

    function getLiquidationData(Loan calldata loan) external view returns (uint256, uint256);
}

contract UniqueValidator is Validator {

    error InvalidDeadline();
    error InvalidValidator();
    error InvalidCollateral();
    error InvalidBorrowAmount();

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
    }


    function execute(LoanManager.NewLoanRequest calldata nlr, address tokenContract, uint256 identifier) external override returns (Loan memory, address strategist) {


        Details memory details = abi.decode(nlr.details, (Details));

        if (address(this) != details.validator) {
            revert InvalidValidator();
        }
        if (block.timestamp > details.deadline) {
            revert InvalidDeadline();
        }
        if (details.token != tokenContract || details.tokenId != identifier) {
            revert InvalidCollateral();
        }

        if (nlr.borrowerDetails.howMuch > details.maxAmount) {
            revert InvalidBorrowAmount();
        }

         strategist = ecrecover(keccak256(nlr.details), nlr.v, nlr.r, nlr.s);


        ConduitTransfer[] memory transfers = new ConduitTransfer[](1);
        transfers[0] = ConduitTransfer(
            ConduitItemType.ERC20,
            nlr.borrowerDetails.what,
            strategist,
            nlr.borrowerDetails.who,
            0,
            nlr.borrowerDetails.howMuch
        );
        ConduitInterface(details.conduit).execute(transfers);
        return (
            Loan({
                borrower: nlr.borrowerDetails.who,
                validator : address(this),
                token : details.token,
                identifier : details.tokenId,
                debtToken : nlr.borrowerDetails.what,
                amount : nlr.borrowerDetails.howMuch,
                rate : details.rate,
                start : block.timestamp,
                duration : details.duration
            }), strategist
        );
    }

    function getOwed(Loan calldata loan) public view override returns (uint256) {
        return loan.amount * loan.rate * (loan.start + loan.duration - block.timestamp);
    }

    function getLiquidationData(Loan calldata loan) public view returns (uint256, uint256) {
        if (loan.start + loan.duration < block.timestamp) {
            revert LoanHealthy();
        }
        //todo dynamic initialask can be a flooracle call or anything youd want to look up here
        return (getOwed(loan), 500 ether);
    }
}

contract LoanManager is ERC721("LoanManager", "LM"), AmountDeriver, ContractOffererInterface, IERC721Receiver {
    using FixedPointMathLib for uint256;
    uint256 private constant OUTOFBOUND_ERROR_SELECTOR = 0x571e08d100000000000000000000000000000000000000000000000000000000;
    uint256 private constant ONE_WORD = 0x20;

    enum Action {
        OPEN,
        REPAY,
        LIQUIDATE
    }
    struct BorrowerDetails {
        address who;
        address what;
        uint256 howMuch;
    }

    struct NewLoanRequest {
        address lender;
        address validator;
        bytes details;
        BorrowerDetails borrowerDetails;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    event LoanOpened(uint256 indexed loanId, Validator.Loan loan);
    event LoanRepaid(uint256 indexed loanId);
    event LoanLiquidated(uint256 indexed loanId, uint256 amount);
    event SeaportCompatibleContractDeployed();

    error InvalidSender();
    error InvalidAction();
    error InvalidLoan(uint256);
    error InvalidAmount();
    error InvalidDeadline();
    error InvalidSignature();
    error LoanHealthy();
    error StateMismatch(uint256);
    error UnsupportedExtraDataVersion(uint8 version);
    error InvalidExtraDataEncoding(uint8 version);

    address public seaport;

    constructor(address consideration) {
        seaport = consideration;
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

        uint8 action = safeCastTo8(_sliceUint(context, 0));
//        uint8 action = uint8(context[1:]);

        if (action == uint8(Action.OPEN)) {

            consideration = new ReceivedItem[](1);
            consideration[0] = ReceivedItem({
            itemType : ItemType.ERC721,
            token : maximumSpent[0].token,
            identifier : maximumSpent[0].identifier,
            amount : 1,
            recipient : payable(address(this))
            });
        } else if (action == uint8(Action.REPAY)) {
            (,Validator.Loan memory loan) = abi.decode(context, (uint8, Validator.Loan));

            offer = new SpentItem[](1);

            offer[0] = SpentItem({
            itemType : ItemType.ERC721,
            token : loan.token,
            identifier : loan.identifier,
            amount : 1
            });

            uint256 owed = Validator(loan.validator).getOwed(loan);
            if (owed > minimumReceived[0].amount) {
                revert InvalidAmount();
            }
            consideration = new ReceivedItem[](1);
            consideration[0] = ReceivedItem({
            itemType : ItemType.ERC20,
            token : loan.debtToken,
            identifier : 0,
            amount : owed,
            recipient : payable(ownerOf(uint(_hashCollateral(loan.token, loan.identifier))))
            });
        } else if (action == uint8(Action.LIQUIDATE)) {
            (, Validator.Loan memory loan) = abi.decode(context, (uint8, Validator.Loan));

            offer = new SpentItem[](1);

            offer[0] = SpentItem(ItemType.ERC721, loan.token, loan.identifier, 1);
            //if the minimumReceived is greater than the entire debt pay the rest back to the owner of the loan
            (uint256 owed, uint256 currentPrice) = Validator(loan.validator).getLiquidationData(loan);
            if (currentPrice > minimumReceived[0].amount) {
                revert InvalidAmount();
            }
            if (currentPrice > owed) {
                consideration = new ReceivedItem[](2);
                consideration[0] = ReceivedItem({
                itemType : ItemType.ERC20,
                token : loan.debtToken,
                identifier : 0,
                amount : currentPrice,
                recipient : payable(ownerOf(uint256(_hashCollateral(loan.token, loan.identifier))))
                });
                consideration[1] = ReceivedItem({
                itemType : ItemType.ERC20,
                token : loan.debtToken,
                identifier : 0,
                amount : minimumReceived[0].amount - currentPrice,
                recipient : payable(loan.borrower)
                });
            } else {
                consideration = new ReceivedItem[](1);
                consideration[0] = ReceivedItem({
                itemType : ItemType.ERC20,
                token : loan.debtToken,
                identifier : 0,
                amount : minimumReceived[0].amount,
                recipient : payable(ownerOf(uint256(_hashCollateral(loan.token, loan.identifier))))
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

        uint8 action = safeCastTo8(_sliceUint(context, 0));

        if (action == uint8(Action.OPEN)) {
            _executeLoanOpen(consideration, context);
        } else if (action == uint8(Action.REPAY)) {
            _executeLoanRepay(context);
        } else if (action == uint8(Action.LIQUIDATE)) {
            _executeLoanLiquidate(offer, consideration, context);
        } else {
            revert InvalidAction();
        }

        return ContractOffererInterface.ratifyOrder.selector;
    }

    //do more work here
    function forgive(Validator.Loan calldata loan) public {
        uint256 loanId = uint256(_hashCollateral(loan.token, loan.identifier));
        if (msg.sender != ownerOf(loanId)) {
            revert InvalidSender();
        }

        _clearLoanId(loanId);
        ERC721(loan.token).transferFrom(address(this), msg.sender, loan.identifier);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, ContractOffererInterface) returns (bool) {
        return interfaceId == type(ContractOffererInterface).interfaceId || interfaceId == type(ERC721).interfaceId || super.supportsInterface(interfaceId);
    }

    // INTERNAL FUNCTIONS
    function _hashCollateral(address token, uint256 tokenId) internal pure returns (bytes32 hash) {
        assembly {
            mstore(0, token) // sets the right most 20 bytes in the first memory slot.
            mstore(0x20, tokenId) // stores tokenId in the second memory slot.
            hash := keccak256(12, 52) // keccak from the 12th byte up to the entire second memory slot.
        }
    }

    function _clearLoanId(uint256 loanId) internal {

        _burn(loanId);
    }

    function _sliceUint(
        bytes memory bs,
        uint256 start
    ) internal pure returns (uint256 x) {
        uint256 length = bs.length;

        assembly {
            let end := add(ONE_WORD, start)

            if lt(length, end) {
                mstore(0, OUTOFBOUND_ERROR_SELECTOR)
                revert(0, ONE_WORD)
            }

            x := mload(add(bs, end))
        }
    }

    function _executeLoanOpen(ReceivedItem[] calldata consideration, bytes calldata context) internal {
        (,NewLoanRequest memory nlr) = abi.decode(context, (uint8, NewLoanRequest));
        {
            (Validator.Loan memory loan, address lender) = Validator(nlr.validator).execute(nlr, consideration[0].token, consideration[0].identifier);

            uint256 loanId = uint256(_hashCollateral(consideration[0].token, consideration[0].identifier));
            _safeMint(lender, loanId);
            emit LoanOpened(loanId, loan);
        }
    }

    function _executeLoanRepay(bytes calldata context) public {
        (, Validator.Loan memory loan) = abi.decode(context, (uint8, Validator.Loan));

        uint256 loanId = uint256(_hashCollateral(loan.token, loan.identifier));

        _clearLoanId(loanId);
        emit LoanRepaid(loanId);
    }

    function _executeLoanLiquidate(SpentItem[] calldata offer, ReceivedItem[] calldata consideration, bytes calldata context) internal {
        address debtToken = consideration[0].token;
        uint256 amount = consideration[0].amount;
        (, Validator.Loan memory loan) = abi.decode(context, (uint8, Validator.Loan));

        uint256 loanId = uint256(_hashCollateral(offer[0].token, offer[0].identifier));

        if (loan.start + loan.duration > block.timestamp) {
            revert LoanHealthy();
        }
        _burn(loanId);
        emit LoanLiquidated(loanId, amount);
    }

    function safeCastTo8(uint256 x) internal pure returns (uint8 y) {
        require(x < 1 << 8);

        y = uint8(x);
    }
}