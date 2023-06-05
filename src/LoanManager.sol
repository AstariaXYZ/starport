pragma solidity =0.8.17;

import {ERC721} from "solmate/tokens/ERC721.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {Bytes32AddressLib} from "solmate/utils/Bytes32AddressLib.sol";

import {ConduitTransfer, ConduitItemType} from "seaport-types/src/conduit/lib/ConduitStructs.sol";
import {ItemType, OfferItem, Schema, SpentItem, ReceivedItem, OrderParameters} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {ConduitControllerInterface} from "seaport-types/src/interfaces/ConduitControllerInterface.sol";
import {ConsiderationInterface} from "seaport-types/src/interfaces/ConsiderationInterface.sol";
import {ConduitInterface as Conduit} from "seaport-types/src/interfaces/ConduitInterface.sol";
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

interface IVault {
    function getConduit() external view returns (address);
    function verifyLoanSignature(bytes32 loanHash, uint8 v, bytes32 r, bytes32 s) external view returns (bool);
}

interface Validator {
    struct Loan {
        address validator;
        address token;
        uint256 identifier;
        address debtToken;
        address vault;
        uint256 amount;
        uint256 rate;
        uint256 end;
        uint256 initialAsk;
    }

    function execute(LoanManager.NewLoanRequest calldata nlr, address token, uint256 identifier) external returns (ConduitTransfer memory, Loan memory);

}

contract UniqueValidator is Validator {

    struct Details {
        address vault;
        address token;
        uint256 tokenId;
        uint256 maxAmount;
        uint256 rate; //rate per second
        uint256 duration;
        uint256 initialAsk;
    }


    function execute(LoanManager.NewLoanRequest calldata nlr, address tokenContract, uint256 identifier) external override returns (ConduitTransfer memory, Loan memory) {

        if (address(this) != nlr.validator) {
            revert("Invalid Validator");
        }

        Details memory details = abi.decode(nlr.details, (Details));

        if (details.token != tokenContract || details.tokenId != identifier) {
            revert("Invalid Token");
        }

        if (nlr.borrowerDetails.howMuch > details.maxAmount) {
            revert ("Invalid Borrow Amount");
        }
        if (!IVault(details.vault).verifyLoanSignature(keccak256(nlr.details), nlr.v, nlr.r, nlr.s)) {
            revert ("Invalid Signature for loan");
        }


        // ConduitItemType itemType;
        //    address token;
        //    address from;
        //    address to;
        //    uint256 identifier;
        //    uint256 amount;
        return (
        ConduitTransfer(
            ConduitItemType.ERC20,
            nlr.borrowerDetails.what,
            details.vault,
            nlr.borrowerDetails.who,
            0,
            nlr.borrowerDetails.howMuch
        ),
        Loan({
        validator : address(this),
        token : details.token,
        identifier : details.tokenId,
        debtToken : nlr.borrowerDetails.what,
        vault : details.vault,
        amount : nlr.borrowerDetails.howMuch,
        rate : details.rate,
        end : block.timestamp + details.duration,
        initialAsk : details.initialAsk
        })
        );
    }
}

contract LoanManager is ERC721("LoanManager", "LM"), ContractOffererInterface, AmountDeriver, IERC721Receiver {

    using FixedPointMathLib for uint256;

    struct BorrowerDetails {
        address who;
        address what;
        uint256 howMuch;
    }

    struct NewLoanRequest {
        uint256 deadline;
        address validator;
        BorrowerDetails borrowerDetails;
        bytes details;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }
    event LoanOpened(uint256 indexed loanId, Validator.Loan loan);
    event LoanRepaid(uint256 indexed loanId);
    event LoanLiquidated(uint256 indexed loanId, uint256 amount);


    mapping(uint256 => bytes32) public collateralState;

    mapping(address => mapping(address => uint256)) public liabilities; //vault / weth / negative balance

    ConduitControllerInterface public CI;

    ConsiderationInterface public seaport;

    Conduit public conduit;
    bytes32 public conduitKey;

    constructor(address consideration) {
        seaport = ConsiderationInterface(consideration);
        (, , address conduitController) = seaport.information();
        CI = ConduitControllerInterface(conduitController);

        conduitKey = Bytes32AddressLib.fillLast12Bytes(address(this));

        conduit = Conduit(CI.createConduit(conduitKey, address(this)));
        CI.updateChannel(
            address(conduit),
            address(seaport),
            true
        );
    }




    // MODIFIERS

    modifier onlySeaport {
        if (msg.sender != address(seaport)) {
            revert("Invalid Conduit");
        }
        _;
    }


    // PUBLIC FUNCTIONS

    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) public virtual returns (bytes4) {
        if (data.length == 0) {
            revert("invalid data");
        }

        bytes32 hash = _hashCollateral(msg.sender, tokenId);
        uint256 loanId = uint256(hash);

        if (collateralState[loanId] != 0) {
            revert("asset in use");
        }

        (NewLoanRequest memory nlr) = abi.decode(data, (NewLoanRequest));

        if (block.timestamp > nlr.deadline) {
            revert("loan deadline passed");
        }


        (ConduitTransfer memory x, Validator.Loan memory loan) = Validator(nlr.validator).execute(nlr, msg.sender, tokenId);

        ConduitTransfer[] memory xx = new ConduitTransfer[](1);
        xx[0] = x;
        Conduit(IVault(loan.vault).getConduit()).execute(xx);
        liabilities[loan.vault][loan.debtToken] += loan.amount;
        collateralState[loanId] = keccak256(abi.encode(loanId, loan));
        _safeMint(from, loanId);
        emit LoanOpened(loanId, loan);
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
        offer = new SpentItem[](1);
        Validator.Loan memory loan = abi.decode(context, (Validator.Loan));

        offer[0] = SpentItem(ItemType.ERC721, loan.token, loan.identifier, 1);
        //if the minimumReceived is greater than the entire debt pay the rest back to the owner of the loan
        uint256 owed = loan.amount + _getInterestMemory(loan, block.timestamp);
        uint256 currentPrice = _locateCurrentAmount({startAmount : loan.initialAsk, endAmount : 1000 wei, startTime : loan.end, endTime : loan.end + 24 hours, roundUp : true});
        if (currentPrice > minimumReceived[0].amount) {
            revert("invalid minimum received");
        }
        if (currentPrice > owed) {
            consideration = new ReceivedItem[](2);
            consideration[0] = ReceivedItem({
            itemType : ItemType.ERC20,
            token : loan.debtToken,
            identifier : 0,
            amount : currentPrice,
            recipient : payable(loan.vault)
            });
            consideration[1] = ReceivedItem({
            itemType : ItemType.ERC20,
            token : loan.debtToken,
            identifier : 0,
            amount : minimumReceived[0].amount - currentPrice,
            recipient : payable(ownerOf(uint256(_hashCollateral(loan.token, loan.identifier))))
            });
        } else {
            consideration = new ReceivedItem[](1);
            consideration[0] = ReceivedItem({
            itemType : ItemType.ERC20,
            token : loan.debtToken,
            identifier : 0,
            amount : minimumReceived[0].amount,
            recipient : payable(loan.vault)
            });
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
    ) external returns (SpentItem[] memory offer, ReceivedItem[] memory consideration) {
        
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

        address debtToken = consideration[0].token;
        uint256 amount = consideration[0].amount;
        bytes32 collateralHash = _hashCollateral(offer[0].token, offer[0].identifier);
        Validator.Loan memory loan = abi.decode(context, (Validator.Loan));

        uint256 loanId = uint256(collateralHash);

        bytes32 incomingState = keccak256(abi.encode(loanId, loan));
        if (incomingState != collateralState[loanId]) {
            revert("invalid loan");
        }

        if (loan.end > block.timestamp) {
            revert("loan healthy");
        }
        if (amount < _locateCurrentAmount({startAmount : loan.initialAsk, endAmount : 1000 wei, startTime : loan.end, endTime : loan.end + 24 hours, roundUp : true})) {
            revert("invalid amount");
        }
        liabilities[loan.vault][debtToken] -= loan.amount;
        _burn(loanId);
        delete collateralState[loanId];
        emit LoanLiquidated(loanId, amount);
        return LoanManager.ratifyOrder.selector;
    }

    function repay(Validator.Loan calldata loan) public {
        bytes32 hash = _hashCollateral(loan.token, loan.identifier);
        uint256 loanId = uint256(hash);
        if (hash != collateralState[loanId]) {
            revert("invalid loan");
        }
    unchecked {
        liabilities[loan.vault][loan.debtToken] -= loan.amount;
    }

        uint payment = loan.amount + _getInterest(loan, block.timestamp);
        ERC20(loan.debtToken).transferFrom(msg.sender, loan.vault, payment);
        _releaseAndBurn(loanId, loan.token, loan.identifier);
        emit LoanRepaid(loanId);
    }

    function releaseNFT(address token, uint256 tokenId) public {
        bytes32 hash = _hashCollateral(msg.sender, tokenId);

        uint256 loanId = uint256(hash);
        if (msg.sender != ownerOf(loanId)) {
            revert("invalid msg.sender");
        }

        if (collateralState[loanId] != 0) {
            revert("active loan");
        }
        _releaseAndBurn(loanId, token, tokenId);
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


    function _releaseAndBurn(uint256 loanId, address token, uint256 tokenId) internal {
        ERC721(token).transferFrom(address(this), ownerOf(loanId), tokenId);
        delete collateralState[loanId];
        _burn(loanId);
    }

    function _getInterest(
        Validator.Loan calldata loan,
        uint256 timestamp
    ) internal pure returns (uint256) {
        uint256 delta_t = timestamp - loan.end;
        return (delta_t * loan.rate).mulWadDown(loan.amount);
    }

    function _getInterestMemory(
        Validator.Loan memory loan,
        uint256 timestamp
    ) internal pure returns (uint256) {
        uint256 delta_t = timestamp - loan.end;
        return (delta_t * loan.rate).mulWadDown(loan.amount);
    }
}