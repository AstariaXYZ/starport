import { Address, hashTypedData, pad, Hex, hexToString } from 'viem'
import { privateKeyToAccount } from 'viem/accounts'
import { decodeAbiParameters } from 'viem'



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


const domain = (verifyingContract: Address, chainId: any) => ({
  version: "0" ,
  chainId,
  verifyingContract: verifyingContract
});

type caveatType = [`0x${string}`, `0x${string}`];

const typeDataMessage = (account: Address, accountNonce: string, singleUse: boolean, salt: Hex, deadline: string, caveats: caveatType) => ({
  account: account, accountNonce: accountNonce, singleUse: true, salt: salt, deadline: deadline, caveats: caveats
});

//verifying contract
//account
//singleUse
//salt
//deadline
//caveats

const args = process.argv.slice(2);

const main = async () => {
  const [signerKeyRaw, verifyingContract, account, accountNonce, singleUse, salt, deadline, caveatsRaw, chainId] = args;
  const signerKey: any = `${signerKeyRaw}`;
  // const signer = privateKeyToAccount(signerKey);//anvil account 1
  const caveats : unknown  = decodeAbiParameters([{ name: 'enforcer', type: 'address' },
    { name: 'data', type: 'bytes' },], caveatsRaw as `0x${string}`);

  const hashData : any = {
    domain: domain(verifyingContract as Address, parseInt(chainId as Hex).toString()),
    types,
    primaryType: "Origination",
    message: typeDataMessage(account as Address, "0", !!parseInt(singleUse as Hex), pad(salt as Hex, {size: 32}), pad(deadline as Hex, {size: 32}), [] as  any)
  };
  const dataHash = hashTypedData(hashData);

  console.log(dataHash);
}

main();