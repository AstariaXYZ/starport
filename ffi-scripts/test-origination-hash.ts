import { Address, hashTypedData, pad, Hex } from "viem";
import { decodeAbiParameters, parseAbiParameters } from "viem";

const types = {
  Origination: [
    {
      name: "account",
      type: "address"
    },
    {
      name: "accountNonce",
      type: "uint256"
    },
    {
      name: "singleUse",
      type: "bool"
    },
    {
      name: "salt",
      type: "bytes32"
    },
    {
      name: "deadline",
      type: "uint256"
    },
    {
      name: "caveats",
      type: "Caveat[]"
    }
  ],
  Caveat: [
    {
      name: "enforcer",
      type: "address"
    },
    {
      name: "data",
      type: "bytes"
    }
  ]
};

const domain = (verifyingContract: Address, chainId: number) => ({
  name: "Starport",
  version: "0",
  chainId: chainId,
  verifyingContract
});

const typeDataMessage = (account: Address, accountNonce: string, singleUse: boolean, salt: Hex, deadline: string, caveats: any) => ({
  account: account, accountNonce: parseInt(accountNonce), singleUse: singleUse, salt: salt, deadline: deadline, caveats: caveats[0]
});

const args = process.argv.slice(2);

const main = async () => {
  const [signerKeyRaw, verifyingContract, account, accountNonce, singleUse, salt, deadline, caveatsRaw, chainId] = args;
  const caveats: any = decodeAbiParameters(parseAbiParameters("(address enforcer,bytes data)[]"), caveatsRaw as `0x${string}`);
  const hashData: any = {
    domain: domain(verifyingContract as Address, parseInt(chainId as Hex)),
    types,
    primaryType: "Origination",
    message: typeDataMessage(account as Address, accountNonce, !!parseInt(singleUse as Hex), pad(salt as Hex, {size: 32}), parseInt(deadline as Hex).toString(), caveats as  any)
  };

  const dataHash: Hex = hashTypedData(hashData);
  console.log(dataHash);
};

main();