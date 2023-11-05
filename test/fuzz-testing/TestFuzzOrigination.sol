// SPDX-License-Identifier: MIT
import "starport-test/StarportTest.sol";
import "starport-test/utils/Bound.sol";

contract TestFuzzOrigination is StarportTest, Bound {
    function setUp() public override {
        super.setUp();

        vm.warp(100_000);
    }

    function _boundTokenByItemType(ItemType itemType) internal view override returns (address token) {
        if (itemType == ItemType.ERC20) {
            token = address(erc20s[0]);
        } else if (itemType == ItemType.ERC721) {
            token = address(erc721s[0]);
        } else if (itemType == ItemType.ERC1155) {
            token = address(erc1155s[0]);
        } else {
            revert("invalid itemType");
        }
    }

    function _issueAndApproveTarget(SpentItem[] memory what, address who, address target) internal {
        vm.startPrank(who);
        for (uint256 i = 0; i < what.length; i++) {
            if (what[i].itemType == ItemType.ERC20) {
                vm.assume(TestERC20(what[i].token).totalSupply() + what[i].amount < type(uint256).max);
                TestERC20(what[i].token).mint(who, what[i].amount);
                TestERC20(what[i].token).approve(address(target), type(uint256).max);
            } else if (what[i].itemType == ItemType.ERC721) {
                TestERC721(what[i].token).mint(who, what[i].identifier);
                TestERC721(what[i].token).approve(address(target), what[i].identifier);
            } else if (what[i].itemType == ItemType.ERC1155) {
                TestERC1155(what[i].token).mint(who, what[i].identifier, what[i].amount);
                TestERC1155(what[i].token).setApprovalForAll(address(target), true);
            }
        }
        vm.stopPrank();
    }

    function boundPricingData() internal view returns (bytes memory pricingData) {
        BasePricing.Details memory details = BasePricing.Details({
            rate: _boundMin(0, (uint256(1e16) * 150) / (365 * 1 days)),
            carryRate: _boundMin(0, uint256((1e16 * 100)))
        });
        pricingData = abi.encode(details);
    }

    function boundStatusData() internal view returns (bytes memory statusData) {
        FixedTermStatus.Details memory details = FixedTermStatus.Details({loanDuration: _boundMin(1 hours, 1095 days)});
        statusData = abi.encode(details);
    }

    function boundSettlementData() internal view returns (bytes memory settlementData) {
        DutchAuctionSettlement.Details memory details = DutchAuctionSettlement.Details({
            startingPrice: _boundMin(1000 ether, 501 ether),
            endingPrice: _boundMin(500 ether, 1 ether),
            window: _boundMin(1 days, 100 days)
        });
        settlementData = abi.encode(details);
    }

    function boundFuzzLenderTerms() internal view returns (Starport.Terms memory terms) {
        terms.status = address(status);
        terms.settlement = address(settlement);
        terms.pricing = address(pricing);
        terms.pricingData = boundPricingData();
        terms.statusData = boundStatusData();
        terms.settlementData = boundSettlementData();
    }

    struct FuzzLoan {
        address custodian; //where the collateral is being held
        address issuer; //the capital issuer/lender
        address fulfiller;
        Fuzz.SpentItem[] collateral; //array of collateral
    }

    function boundFuzzLoan(FuzzLoan memory params) internal returns (Starport.Loan memory loan) {
        uint256 length = _boundMin(1, 4);
        loan.terms = boundFuzzLenderTerms();
        uint256 i = 0;
        if (length > params.collateral.length) {
            length = params.collateral.length;
        }
        SpentItem[] memory ret = new SpentItem[](length);

        console.log(params.collateral.length);
        for (; i < length; i++) {
            ret[i] = _boundSpentItem(params.collateral[i]);
        }
        loan.collateral = ret;
        SpentItem[] memory debt = new SpentItem[](1);
        debt[0] = SpentItem({
            itemType: ItemType.ERC20,
            identifier: 0,
            amount: _boundMin(1, type(uint64).max),
            token: address(erc20s[0])
        });
        loan.debt = debt;
        loan.borrower = borrower.addr;
        loan.custodian = SP.defaultCustodian();
        loan.issuer = lender.addr;
        return loan;
    }

    function willArithmeticOverflow(Starport.Loan memory loan) internal view {
        FixedTermStatus.Details memory statusDetails = abi.decode(loan.terms.statusData, (FixedTermStatus.Details));
        BasePricing.Details memory pricingDetails = abi.decode(loan.terms.pricingData, (BasePricing.Details));
        try BasePricing(loan.terms.pricing).getPaymentConsideration(loan) returns (
            SpentItem[] memory repayConsideration, SpentItem[] memory carryConsideration
        ) {} catch {
            revert("arithmetic overflow");
        }
    }

    function testFuzzNewOrigination(FuzzLoan memory params) public {
        vm.assume(params.collateral.length > 1);
        Starport.Loan memory loan = boundFuzzLoan(params);
        willArithmeticOverflow(loan);
        _issueAndApproveTarget(loan.collateral, loan.borrower, address(SP));
        _issueAndApproveTarget(loan.debt, loan.issuer, address(SP));

        bytes32 borrowerSalt = _boundMinBytes32(0, type(uint256).max);
        bytes32 lenderSalt = _boundMinBytes32(0, type(uint256).max);
        address fulfiller = _toAddress(_boundMin(_toUint(params.fulfiller), 100));
        newLoan(loan, borrowerSalt, lenderSalt, fulfiller);
    }
}
