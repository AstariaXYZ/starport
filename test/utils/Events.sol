//
//        bytes32 lienOpenTopic = bytes32(0x57cb72d73c48fadf55428537f6c9efbe080ae111339b0c5af42d9027ed20ba17);
//        for (uint256 i = 0; i < logs.length; i++) {
//            if (logs[i].topics[0] == lienOpenTopic) {
//                (loanId, loan) = abi.decode(logs[i].data, (uint256, LoanManager.Loan));
//                break;
//            }
//        }
