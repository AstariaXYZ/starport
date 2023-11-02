pragma solidity ^0.8.17;

import "starport-test/AstariaV1Test.sol";
import {StarPortLib, Actions} from "starport-core/lib/StarPortLib.sol";
import {DeepEq} from "starport-test/utils/DeepEq.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";
import {SpentItemLib} from "seaport-sol/src/lib/SpentItemLib.sol";
import {Originator} from "starport-core/originators/Originator.sol";
import {CaveatEnforcer} from "starport-core/enforcers/CaveatEnforcer.sol";
import "forge-std/console2.sol";

contract TestAstariaV1Hook is AstariaV1Test, DeepEq {
    using Cast for *;
    using FixedPointMathLib for uint256;
    using stdStorage for StdStorage;
    using {StarPortLib.getId} for LoanManager.Loan;
    // recaller is not the lender, liquidation amount is a dutch auction

    //function isActive(LoanManager.Loan calldata loan) external view override returns (bool) {
    //        Details memory details = abi.decode(loan.terms.hookData, (Details));
    //        uint256 tokenId = loan.getId();
    //        uint64 start = recalls[tokenId].start;
    //        return !(start > 0 && start + details.recallWindow < block.timestamp);
    //    }
    //
    //    function isRecalled(LoanManager.Loan calldata loan) external view override returns (bool) {
    //        Details memory details = abi.decode(loan.terms.hookData, (Details));
    //        uint256 tokenId = loan.getId();
    //        Recall memory recall = recalls[tokenId];
    //        return (recall.start + details.recallWindow > block.timestamp) && recall.start != 0;
    //    }
    // function getRecallRate(LoanManager.Loan calldata loan) external view returns (uint256) {
    //        Details memory details = abi.decode(loan.terms.hookData, (Details));
    //        uint256 loanId = loan.getId();
    //        // calculates the porportion of time elapsed, then multiplies times the max rate
    //        return details.recallMax.mulWad((block.timestamp - recalls[loanId].start).divWad(details.recallWindow));
    //    }
    //
    //    function recall(LoanManager.Loan memory loan, address conduit) external {
    //        Details memory details = abi.decode(loan.terms.hookData, (Details));
    //
    //        if ((loan.start + details.honeymoon) > block.timestamp) {
    //            revert RecallBeforeHoneymoonExpiry();
    //        }
    //
    //        if (loan.issuer != msg.sender && loan.borrower != msg.sender) {
    //            // (,, address conduitController) = seaport.information();
    //            // validate that the provided conduit is owned by the msg.sender
    //            // if (ConduitControllerInterface(conduitController).ownerOf(conduit) != msg.sender) {
    //            //     revert InvalidConduit();
    //            // }
    //            AdditionalTransfer[] memory recallConsideration = _generateRecallConsideration(
    //                loan, 0, details.recallStakeDuration, 1e18, msg.sender, payable(address(this))
    //            );
    //            if (ConduitInterface(conduit).execute(recallConsideration) != ConduitInterface.execute.selector) {
    //                revert AdditionalTransferError();
    //            }
    //        }
    //        // get conduitController
    //
    //        bytes memory encodedLoan = abi.encode(loan);
    //
    //        uint256 loanId = uint256(keccak256(encodedLoan));
    //
    //        if (!LM.active(loanId)) revert LoanDoesNotExist();
    //
    //        recalls[loanId] = Recall(payable(msg.sender), uint64(block.timestamp));
    //        emit Recalled(loanId, msg.sender, loan.start + details.recallWindow);
    //    }
    //
    //    // transfers all stake to anyone who asks after the LM token is burned
    //    function withdraw(LoanManager.Loan memory loan, address payable receiver) external {
    //        Details memory details = abi.decode(loan.terms.hookData, (Details));
    //        bytes memory encodedLoan = abi.encode(loan);
    //        uint256 loanId = uint256(keccak256(encodedLoan));
    //
    //        // loan has not been refinanced, loan is still active. LM.tokenId changes on refinance
    //        if (!LM.inactive(loanId)) revert LoanHasNotBeenRefinanced();
    //
    //        Recall storage recall = recalls[loanId];
    //        // ensure that a recall exists for the provided tokenId, ensure that the recall
    //        if (recall.start == 0 || recall.recaller == address(0)) {
    //            revert WithdrawDoesNotExist();
    //        }
    //
    //        if (loan.issuer != recall.recaller && loan.borrower != recall.recaller) {
    //            AdditionalTransfer[] memory recallConsideration =
    //                _generateRecallConsideration(loan, 0, details.recallStakeDuration, 1e18, address(this), receiver);
    //            recall.recaller = payable(address(0));
    //            recall.start = 0;
    //
    //            for (uint256 i; i < recallConsideration.length;) {
    //                if (loan.debt[i].itemType != ItemType.ERC20) revert InvalidStakeType();
    //
    //                ERC20(loan.debt[i].token).transfer(receiver, recallConsideration[i].amount);
    //
    //                unchecked {
    //                    ++i;
    //                }
    //            }
    //        }
    //
    //        emit Withdraw(loanId, receiver);
    //    }
    //
    //    function _getRecallStake(LoanManager.Loan memory loan, uint256 start, uint256 end)
    //        internal
    //        view
    //        returns (uint256[] memory recallStake)
    //    {
    //        BasePricing.Details memory details = abi.decode(loan.terms.pricingData, (BasePricing.Details));
    //        recallStake = new uint256[](loan.debt.length);
    //        for (uint256 i; i < loan.debt.length;) {
    //            recallStake[i] = BasePricing(loan.terms.pricing).getInterest(loan, details.rate, start, end, i);
    //
    //            unchecked {
    //                ++i;
    //            }
    //        }
    //    }
    //
    function testIsActive() public {
        LoanManager.Terms memory terms = LoanManager.Terms({
            hook: address(hook),
            handler: address(handler),
            pricing: address(pricing),
            pricingData: defaultPricingData,
            handlerData: defaultHandlerData,
            hookData: defaultHookData
        });
        LoanManager.Loan memory loan =
            _createLoan721Collateral20Debt({lender: lender.addr, borrowAmount: 1e18, terms: terms});
        uint256 loanId = loan.getId();
        assert(AstariaV1SettlementHook(loan.terms.hook).isActive(loan));
    }

    function testIsRecalledInsideWindow() public {
        LoanManager.Terms memory terms = LoanManager.Terms({
            hook: address(hook),
            handler: address(handler),
            pricing: address(pricing),
            pricingData: defaultPricingData,
            handlerData: defaultHandlerData,
            hookData: defaultHookData
        });
        LoanManager.Loan memory loan =
            _createLoan721Collateral20Debt({lender: lender.addr, borrowAmount: 1e18, terms: terms});
        uint256 loanId = loan.getId();

        BaseRecall.Details memory details = abi.decode(loan.terms.hookData, (BaseRecall.Details));

        erc20s[0].mint(address(this), 10e18);
        erc20s[0].approve(loan.terms.hook, 10e18);

        skip(details.honeymoon);
        AstariaV1SettlementHook(loan.terms.hook).recall(loan);
        (address recaller, uint64 recallStart) = AstariaV1SettlementHook(loan.terms.hook).recalls(loanId);
        skip(details.recallWindow - 1);
        assert(AstariaV1SettlementHook(loan.terms.hook).isActive(loan));
        assert(AstariaV1SettlementHook(loan.terms.hook).isRecalled(loan));
    }

    function testIsRecalledOutsideWindow() public {
        LoanManager.Terms memory terms = LoanManager.Terms({
            hook: address(hook),
            handler: address(handler),
            pricing: address(pricing),
            pricingData: defaultPricingData,
            handlerData: defaultHandlerData,
            hookData: defaultHookData
        });
        LoanManager.Loan memory loan =
            _createLoan721Collateral20Debt({lender: lender.addr, borrowAmount: 1e18, terms: terms});
        uint256 loanId = loan.getId();
        BaseRecall.Details memory details = abi.decode(loan.terms.hookData, (BaseRecall.Details));

        erc20s[0].mint(address(this), 10e18);
        erc20s[0].approve(loan.terms.hook, 10e18);

        skip(details.honeymoon);
        AstariaV1SettlementHook(loan.terms.hook).recall(loan);
        (address recaller, uint64 recallStart) = AstariaV1SettlementHook(loan.terms.hook).recalls(loanId);
        skip(details.recallWindow + 1);
        assert(!AstariaV1SettlementHook(loan.terms.hook).isActive(loan));
        assert(!AstariaV1SettlementHook(loan.terms.hook).isRecalled(loan));
    }

    function testGenerateRecallConsideration() public {
        LoanManager.Terms memory terms = LoanManager.Terms({
            hook: address(hook),
            handler: address(handler),
            pricing: address(pricing),
            pricingData: defaultPricingData,
            handlerData: defaultHandlerData,
            hookData: defaultHookData
        });
        LoanManager.Loan memory loan =
            _createLoan721Collateral20Debt({lender: lender.addr, borrowAmount: 1e18, terms: terms});
        uint256 loanId = loan.getId();

        BaseRecall.Details memory recallDetails = abi.decode(loan.terms.hookData, (BaseRecall.Details));
        BasePricing.Details memory pricingDetails = abi.decode(loan.terms.pricingData, (BasePricing.Details));
        //compute interest across a band from 0 to recallStakeDuration instead of from loan.start to end
        uint256 recallStake = BasePricing(loan.terms.pricing).getInterest(
            loan,
            pricingDetails.rate,
            0,
            recallDetails.recallStakeDuration,
            0 //index of the loan
        );
        uint256 proportion = 1e18;
        AdditionalTransfer[] memory recallConsideration = AstariaV1SettlementHook(loan.terms.hook)
            .generateRecallConsideration(loan, proportion, payable(address(this)), payable(loan.issuer));
        assertEq(recallConsideration[0].token, address(erc20s[0]));
        assertEq(recallConsideration[0].amount, recallStake);
        assert(recallConsideration.length == 1);
        proportion = 5e17;
        recallConsideration = AstariaV1SettlementHook(loan.terms.hook).generateRecallConsideration(
            loan, proportion, payable(address(this)), payable(loan.issuer)
        );
        assertEq(recallConsideration[0].token, address(erc20s[0]));
        assertEq(recallConsideration[0].amount, recallStake / 2);
        assert(recallConsideration.length == 1);
    }

    // function getRecallRate(LoanManager.Loan calldata loan) external view returns (uint256) {
    //        Details memory details = abi.decode(loan.terms.hookData, (Details));
    //        uint256 loanId = loan.getId();
    //        // calculates the porportion of time elapsed, then multiplies times the max rate
    //        return details.recallMax.mulWad((block.timestamp - recalls[loanId].start).divWad(details.recallWindow));
    //    }

    function testRecallRateEmptyRecall() public {
        LoanManager.Terms memory terms = LoanManager.Terms({
            hook: address(hook),
            handler: address(handler),
            pricing: address(pricing),
            pricingData: defaultPricingData,
            handlerData: defaultHandlerData,
            hookData: defaultHookData
        });
        LoanManager.Loan memory loan =
            _createLoan721Collateral20Debt({lender: lender.addr, borrowAmount: 1e18, terms: terms});
        BaseRecall.Details memory hookDetails = abi.decode(loan.terms.hookData, (BaseRecall.Details));
        uint256 recallRate = AstariaV1SettlementHook(loan.terms.hook).getRecallRate(loan);
        uint256 computedRecallRate =
            hookDetails.recallMax.mulWad((block.timestamp - 0).divWad(hookDetails.recallWindow));
        assertEq(recallRate, computedRecallRate);
    }

    function testRecallRateActiveRecall() public {
        LoanManager.Terms memory terms = LoanManager.Terms({
            hook: address(hook),
            handler: address(handler),
            pricing: address(pricing),
            pricingData: defaultPricingData,
            handlerData: defaultHandlerData,
            hookData: defaultHookData
        });
        LoanManager.Loan memory loan =
            _createLoan721Collateral20Debt({lender: lender.addr, borrowAmount: 1e18, terms: terms});
        uint256 loanId = loan.getId();
        BaseRecall.Details memory hookDetails = abi.decode(loan.terms.hookData, (BaseRecall.Details));

        erc20s[0].mint(address(this), 10e18);
        erc20s[0].approve(loan.terms.hook, 10e18);

        skip(hookDetails.honeymoon);
        AstariaV1SettlementHook(loan.terms.hook).recall(loan);
        (address recaller, uint64 recallStart) = AstariaV1SettlementHook(loan.terms.hook).recalls(loanId);
        uint256 recallRate = AstariaV1SettlementHook(loan.terms.hook).getRecallRate(loan);
        uint256 computedRecallRate =
            hookDetails.recallMax.mulWad((block.timestamp - recallStart).divWad(hookDetails.recallWindow));
        assertEq(recallRate, computedRecallRate);
    }

    //TODO: this needs to be done because withdraw is being looked at
    function testRecallWithdraw() public {
        LoanManager.Terms memory terms = LoanManager.Terms({
            hook: address(hook),
            handler: address(handler),
            pricing: address(pricing),
            pricingData: defaultPricingData,
            handlerData: defaultHandlerData,
            hookData: defaultHookData
        });
        LoanManager.Loan memory loan =
            _createLoan721Collateral20Debt({lender: lender.addr, borrowAmount: 1e18, terms: terms});
        uint256 loanId = loan.getId();
        BaseRecall.Details memory hookDetails = abi.decode(loan.terms.hookData, (BaseRecall.Details));

        erc20s[0].mint(address(this), 10e18);
        erc20s[0].approve(loan.terms.hook, 10e18);

        skip(hookDetails.honeymoon);
        AstariaV1SettlementHook(loan.terms.hook).recall(loan);

        vm.mockCall(address(LM), abi.encodeWithSelector(LM.inactive.selector, loanId), abi.encode(true));

        //        (address recaller, uint64 recallStart) = AstariaV1SettlementHook(loan.terms.hook).recalls(loanId);
    }
}
