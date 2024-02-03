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

import {Starport} from "starport-core/Starport.sol";
import {Pricing} from "starport-core/Pricing.sol";
import {Validation} from "starport-core/lib/Validation.sol";
import {StarportLib, AdditionalTransfer} from "starport-core/lib/StarportLib.sol";

import {SpentItem, ItemType, ReceivedItem} from "seaport-types/src/lib/ConsiderationStructs.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";

contract SimpleInterestPricing is Pricing {
    using FixedPointMathLib for uint256;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STRUCTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    struct Details {
        uint256 rate;
        uint256 carryRate;
        uint256 decimals;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CONSTRUCTOR                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    constructor(Starport SP_) Pricing(SP_) {}

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     PUBLIC FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    // @inheritdoc Pricing
    function getPaymentConsideration(Starport.Loan calldata loan)
        public
        view
        virtual
        override
        returns (SpentItem[] memory repayConsideration, SpentItem[] memory carryConsideration)
    {
        Details memory details = abi.decode(loan.terms.pricingData, (Details));
        if (details.carryRate > 0 && loan.issuer != loan.originator) {
            carryConsideration = new SpentItem[](loan.debt.length);
        }

        repayConsideration = new SpentItem[](loan.debt.length);

        uint256 i = 0;
        for (; i < loan.debt.length;) {
            uint256 interest = getInterest(loan, details.rate, loan.start, block.timestamp, i, details.decimals);

            if (interest == 0 && loan.debt[i].itemType == ItemType.ERC20) interest = 1;
            if (carryConsideration.length > 0) {
                carryConsideration[i] = SpentItem({
                    itemType: loan.debt[i].itemType,
                    identifier: loan.debt[i].identifier,
                    amount: (interest * details.carryRate) / 10 ** details.decimals,
                    token: loan.debt[i].token
                });
                repayConsideration[i] = SpentItem({
                    itemType: loan.debt[i].itemType,
                    identifier: loan.debt[i].identifier,
                    amount: loan.debt[i].amount + interest - carryConsideration[i].amount,
                    token: loan.debt[i].token
                });
            } else {
                repayConsideration[i] = SpentItem({
                    itemType: loan.debt[i].itemType,
                    identifier: loan.debt[i].identifier,
                    amount: loan.debt[i].amount + interest,
                    token: loan.debt[i].token
                });
            }
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Computes the interest
     * @param delta_t The time delta
     * @param amount The amount to compute the interest for
     * @param rate The interest rate
     * @param decimals The decimals of the base asset
     */
    function calculateInterest(uint256 delta_t, uint256 amount, uint256 rate, uint256 decimals)
        public
        pure
        virtual
        returns (uint256)
    {
        return StarportLib.calculateSimpleInterest(delta_t, amount, rate, decimals);
    }

    /**
     * @dev Computes the interest for a given loan
     * @param loan The loan to compute the interest for
     * @param rate The interest rate
     * @param start The start time frame
     * @param end The end time frame
     * @param index The index of the debt to compute the interest for
     * @param decimals The decimals of the debt asset
     */
    function getInterest(
        Starport.Loan calldata loan,
        uint256 rate,
        uint256 start,
        uint256 end,
        uint256 index,
        uint256 decimals
    ) public pure returns (uint256) {
        uint256 delta_t = end - start;
        return calculateInterest(delta_t, loan.debt[index].amount, rate, decimals);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      EXTERNAL FUNCTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    // @inheritdoc Validation
    function validate(Starport.Loan calldata loan) external pure override returns (bytes4) {
        Details memory details = abi.decode(loan.terms.pricingData, (Details));
        return (details.decimals > 0) ? Validation.validate.selector : bytes4(0xFFFFFFFF);
    }

    // @inheritdoc Pricing
    function getRefinanceConsideration(Starport.Loan calldata loan, bytes memory newPricingData, address)
        external
        view
        virtual
        override
        returns (
            SpentItem[] memory repayConsideration,
            SpentItem[] memory carryConsideration,
            AdditionalTransfer[] memory additionalConsideration
        )
    {
        (additionalConsideration);
        Details memory oldDetails = abi.decode(loan.terms.pricingData, (Details));
        Details memory newDetails = abi.decode(newPricingData, (Details));

        if (oldDetails.decimals == newDetails.decimals && (newDetails.rate < oldDetails.rate)) {
            (repayConsideration, carryConsideration) = getPaymentConsideration(loan);
        } else {
            revert InvalidRefinance();
        }
    }
}
