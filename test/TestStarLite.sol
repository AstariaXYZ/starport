pragma solidity =0.8.17;


import {MockERC721} from "solmate/test/utils/mocks/MockERC721.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import "forge-std/Test.sol";

import "src/LoanManager.sol";

contract TestNFT is MockERC721 {
    constructor() MockERC721("TestNFT", "TNFT") {}
}

contract TestToken is MockERC20 {
    constructor() MockERC20("TestToken", "TTKN", 18) {}
}

contract TestStarLite is Test, IVault, IERC721Receiver {

    address conduit;
    bytes32 conduitKey;

    address strategist;
    address seaportAddr;

    ConduitControllerInterface CI;
    function setUp() public {
       seaportAddr = address(0x00000000000000ADc04C56Bf30aC9d3c0aAF14dC);

        ConsiderationInterface seaport = ConsiderationInterface(seaportAddr);
        (, , address conduitController) = seaport.information();

        CI = ConduitControllerInterface(conduitController);
        conduitKey = Bytes32AddressLib.fillLast12Bytes(address(this));

        conduit = CI.createConduit(conduitKey, address(this));
        CI.updateChannel(
            address(conduit),
            address(seaport),
            true
        );
    }

    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) external override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }



    function getConduit() external view returns (address) {
        return conduit;
    }

    function verifyLoanSignature(bytes32 loanHash, uint8 v, bytes32 r, bytes32 s) external view returns (bool) {

        return strategist == ecrecover(loanHash, v, r, s);
    }

    function testNewLoan() public {

        TestNFT nft = new TestNFT();
        TestToken debtToken = new TestToken();

        vm.label(address(debtToken), "what");
        nft.mint(address(this), 1);




        LoanManager lm = new LoanManager(seaportAddr);

        {

            //setup lender and borrower approvals
            debtToken.approve(conduit, 100000);
            debtToken.mint(address(this),1000);

            nft.setApprovalForAll(address(lm), true);
            CI.updateChannel(
                address(conduit),
                address(lm),
                true
            );
        }


        UniqueValidator uv = new UniqueValidator();

        UniqueValidator.Details memory loanDetails = UniqueValidator.Details({
        vault : address(this),
        token : address(nft),
        tokenId : 1,
        maxAmount : 100,
        rate : 1,
        duration : 1000,
        initialAsk : 5000
        });

        uint256 strategistKey;
        (strategist, strategistKey) = makeAddrAndKey("strategist");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(strategistKey, keccak256(abi.encode(loanDetails)));


        _executeNLR(nft, address(lm), LoanManager.NewLoanRequest({
        deadline : block.timestamp + 100,
        validator : address(uv),
        borrowerDetails : LoanManager.BorrowerDetails({
        who : address(this),
        what : address(debtToken),
        howMuch : 100
        }),
        details : abi.encode(loanDetails),
        v : v,
        r : r,
        s : s
        }));

    }

    function _executeNLR(TestNFT nft, address lm, LoanManager.NewLoanRequest memory nlr) internal {
        nft.safeTransferFrom(address(this), lm, 1, abi.encode(nlr));
    }
}