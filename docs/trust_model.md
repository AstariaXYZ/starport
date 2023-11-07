# Starport Trust Model

### Core contracts (Starport, Custodian)

Core contracts are trusted by all transactors as a source of truth.

The `Starport.Loan` struct hashes all data into the ERC-721 `tokenId`. Loans that `originate` in block must not be able to be repaid, refinanced, or settled. This ensures the uniqueness of the `tokenId`.

#### Starport
- Enforcer Loan struct mutations though `tokenId`
    - `tokenId` creation during originate
    - `tokenId` deletion after repayment
    - `tokenId` deletion after settlement
    - `tokenId` creation and deletion during refinance
    - Any time a `Starport.Loan` is modified, the `tokenId` must mutate
    - Status record of a `tokenId` as `ACTIVE` or `INACTIVE`
- Enforce origination agreements
    - Enforce `loan.collateral` transfers from the `loan.borrower` to `loan.custodian`
    - Enforce `loan.debt` transfers from the `loan.lender` to the `loan.borrower`
    - Enforce borrower caveats if `loan.borrower != msg.sender`, or borrower approved `msg.sender`
    - Enforce lender caveats if `lender != msg.sender`, or lender approved `msg.sender`
    - Create new `tokenId`
    - Mint `tokenId` if the `loan.issuer` is a contract
    - Enforce the transfer of `additionalTransfers`
- Enforce refinance
    - Delete incoming `tokenId`
    - Enforcer repayment transfers from `lender` (refinancing lender) to `loan.issuer` provided by `Pricing.getRefinanceConsideration()`
    - Enforcer carry transfers from `lender` (refinancing lender) to `loan.originator` provided by `Pricing.getRefinanceConsideration()`
        - prevent transfers of zero amounts
        - prevent payments must match the `loan.debt.length` of the corresponding `tokenId`
        - `carryPayment.length` must be`0` or equal to `loan.debt.length`
    - Mutate `Starport.Loan` to reflect repayment of the original loan by the refinancing lender
    - Enforce lender caveats if `lender != msg.sender`, or the lender has approved `msg.sender`

#### Custodian
- Enforce return of the collateral
- Enforce repayment through Seaport
- Enforce settlement through Seaport

### Modules (Pricing, Status, Settlement)
All modules are considered untrusted by the core contracts. Modules can optionally trust each other but it is not a strict requirement for implementation.
#### Pricing
##### getPaymentConsideration
```solidity
    function getPaymentConsideration(Starport.Loan memory loan)
        public
        view
        virtual
        returns (SpentItem[] memory, SpentItem[] memory);
```
- returns the consideration and carry that the collateral can be purchased for (repayment) from the `Custodian` through Seaport
- can return a consideration array of size 0, or an array element with an amount 0

##### getRefinanceConsideration
```solidity
    function getRefinanceConsideration(Starport.Loan memory loan, bytes calldata newPricingData, address fulfiller)
        external
        view
        virtual
        returns (SpentItem[] memory paymentConsideration, SpentItem[] memory carryConsideration, AdditionalTransfer[] memory);
```
- returns the paymentConsideration, carryConsideration, and additionalTransfers that must be paid to refinance a loan
    - `paymentConsideration` will be transferred from the refinancing `lender` to the `loan.issuer` (original lender)
    - `carryConsideration` will be transferred from the refinancing `lender` to the `loan.originator`
    - `additionalTransfers` are optional transfers provided by the modules to enforce mechanisms specific to the module set

#### Status

##### isActive
```solidity
function isActive(Starport.Loan calldata loan) external view virtual returns (bool);
```
- gives the status of whether a loan is in settlement or not
- Loans can go into and out of settlement dependent on dynamically, it is possible for a loan to go into a settlement through an immutable switch but the expectation for the trust model should be that it can waiver
- When `isActive` returns `false` the `loan.collateral` can be purchased though `Seaport` from the `Custodian` with the consideration returned from `Settlement.getSettlementConsideration`

#### Settlement
##### getSettlementConsideration
```solidity
    function getSettlementConsideration(Starport.Loan calldata loan)
        public
        view
        virtual
        returns (ReceivedItem[] memory consideration, address restricted);
```
- returns consideration for the authorized (if address(0) authorized is any) to purchase to collateral though Seaport
- The returned array cannot have zero amounts, but can be size zero